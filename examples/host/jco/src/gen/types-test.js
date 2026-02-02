let dv = new DataView(new ArrayBuffer());
const dataView = mem => dv.buffer === mem.buffer ? dv : dv = new DataView(mem.buffer);

const toInt64 = val => BigInt.asIntN(64, BigInt(val));

function toInt32(val) {
  return val >> 0;
}

const utf8Decoder = new TextDecoder();

const utf8Encoder = new TextEncoder();
let utf8EncodedLen = 0;
function utf8Encode(s, realloc, memory) {
  if (typeof s !== 'string') throw new TypeError('expected a string');
  if (s.length === 0) {
    utf8EncodedLen = 0;
    return 1;
  }
  let buf = utf8Encoder.encode(s);
  let ptr = realloc(0, 0, 1, buf.length);
  new Uint8Array(memory.buffer).set(buf, ptr);
  utf8EncodedLen = buf.length;
  return ptr;
}

let NEXT_TASK_ID = 0n;
function startCurrentTask(componentIdx, isAsync, entryFnName) {
  _debugLog('[startCurrentTask()] args', { componentIdx, isAsync });
  if (componentIdx === undefined || componentIdx === null) {
    throw new Error('missing/invalid component instance index while starting task');
  }
  const tasks = ASYNC_TASKS_BY_COMPONENT_IDX.get(componentIdx);
  
  const nextId = ++NEXT_TASK_ID;
  const newTask = new AsyncTask({ id: nextId, componentIdx, isAsync, entryFnName });
  const newTaskMeta = { id: nextId, componentIdx, task: newTask };
  
  ASYNC_CURRENT_TASK_IDS.push(nextId);
  ASYNC_CURRENT_COMPONENT_IDXS.push(componentIdx);
  
  if (!tasks) {
    ASYNC_TASKS_BY_COMPONENT_IDX.set(componentIdx, [newTaskMeta]);
    return nextId;
  } else {
    tasks.push(newTaskMeta);
  }
  
  return nextId;
}

function endCurrentTask(componentIdx, taskId) {
  _debugLog('[endCurrentTask()] args', { componentIdx });
  componentIdx ??= ASYNC_CURRENT_COMPONENT_IDXS.at(-1);
  taskId ??= ASYNC_CURRENT_TASK_IDS.at(-1);
  if (componentIdx === undefined || componentIdx === null) {
    throw new Error('missing/invalid component instance index while ending current task');
  }
  const tasks = ASYNC_TASKS_BY_COMPONENT_IDX.get(componentIdx);
  if (!tasks || !Array.isArray(tasks)) {
    throw new Error('missing/invalid tasks for component instance while ending task');
  }
  if (tasks.length == 0) {
    throw new Error('no current task(s) for component instance while ending task');
  }
  
  if (taskId) {
    const last = tasks[tasks.length - 1];
    if (last.id !== taskId) {
      throw new Error('current task does not match expected task ID');
    }
  }
  
  ASYNC_CURRENT_TASK_IDS.pop();
  ASYNC_CURRENT_COMPONENT_IDXS.pop();
  
  return tasks.pop();
}
const ASYNC_TASKS_BY_COMPONENT_IDX = new Map();
const ASYNC_CURRENT_TASK_IDS = [];
const ASYNC_CURRENT_COMPONENT_IDXS = [];

class AsyncTask {
  static State = {
    INITIAL: 'initial',
    CANCELLED: 'cancelled',
    CANCEL_PENDING: 'cancel-pending',
    CANCEL_DELIVERED: 'cancel-delivered',
    RESOLVED: 'resolved',
  }
  
  static BlockResult = {
    CANCELLED: 'block.cancelled',
    NOT_CANCELLED: 'block.not-cancelled',
  }
  
  #id;
  #componentIdx;
  #state;
  #isAsync;
  #onResolve = null;
  #entryFnName = null;
  #subtasks = [];
  #completionPromise = null;
  
  cancelled = false;
  requested = false;
  alwaysTaskReturn = false;
  
  returnCalls =  0;
  storage = [0, 0];
  borrowedHandles = {};
  
  awaitableResume = null;
  awaitableCancel = null;
  
  
  constructor(opts) {
    if (opts?.id === undefined) { throw new TypeError('missing task ID during task creation'); }
    this.#id = opts.id;
    if (opts?.componentIdx === undefined) {
      throw new TypeError('missing component id during task creation');
    }
    this.#componentIdx = opts.componentIdx;
    this.#state = AsyncTask.State.INITIAL;
    this.#isAsync = opts?.isAsync ?? false;
    this.#entryFnName = opts.entryFnName;
    
    const {
      promise: completionPromise,
      resolve: resolveCompletionPromise,
      reject: rejectCompletionPromise,
    } = Promise.withResolvers();
    this.#completionPromise = completionPromise;
    
    this.#onResolve = (results) => {
      // TODO: handle external facing cancellation (should likely be a rejection)
      resolveCompletionPromise(results);
    }
  }
  
  taskState() { return this.#state.slice(); }
  id() { return this.#id; }
  componentIdx() { return this.#componentIdx; }
  isAsync() { return this.#isAsync; }
  entryFnName() { return this.#entryFnName; }
  completionPromise() { return this.#completionPromise; }
  
  mayEnter(task) {
    const cstate = getOrCreateAsyncState(this.#componentIdx);
    if (!cstate.backpressure) {
      _debugLog('[AsyncTask#mayEnter()] disallowed due to backpressure', { taskID: this.#id });
      return false;
    }
    if (!cstate.callingSyncImport()) {
      _debugLog('[AsyncTask#mayEnter()] disallowed due to sync import call', { taskID: this.#id });
      return false;
    }
    const callingSyncExportWithSyncPending = cstate.callingSyncExport && !task.isAsync;
    if (!callingSyncExportWithSyncPending) {
      _debugLog('[AsyncTask#mayEnter()] disallowed due to sync export w/ sync pending', { taskID: this.#id });
      return false;
    }
    return true;
  }
  
  async enter() {
    _debugLog('[AsyncTask#enter()] args', { taskID: this.#id });
    
    // TODO: assert scheduler locked
    // TODO: trap if on the stack
    
    const cstate = getOrCreateAsyncState(this.#componentIdx);
    
    let mayNotEnter = !this.mayEnter(this);
    const componentHasPendingTasks = cstate.pendingTasks > 0;
    if (mayNotEnter || componentHasPendingTasks) {
      throw new Error('in enter()'); // TODO: remove
      cstate.pendingTasks.set(this.#id, new Awaitable(new Promise()));
      
      const blockResult = await this.onBlock(awaitable);
      if (blockResult) {
        // TODO: find this pending task in the component
        const pendingTask = cstate.pendingTasks.get(this.#id);
        if (!pendingTask) {
          throw new Error('pending task [' + this.#id + '] not found for component instance');
        }
        cstate.pendingTasks.remove(this.#id);
        this.#onResolve(new Error('failed enter'));
        return false;
      }
      
      mayNotEnter = !this.mayEnter(this);
      if (!mayNotEnter || !cstate.startPendingTask) {
        throw new Error('invalid component entrance/pending task resolution');
      }
      cstate.startPendingTask = false;
    }
    
    if (!this.isAsync) { cstate.callingSyncExport = true; }
    
    return true;
  }
  
  async waitForEvent(opts) {
    const { waitableSetRep, isAsync } = opts;
    _debugLog('[AsyncTask#waitForEvent()] args', { taskID: this.#id, waitableSetRep, isAsync });
    
    if (this.#isAsync !== isAsync) {
      throw new Error('async waitForEvent called on non-async task');
    }
    
    if (this.status === AsyncTask.State.CANCEL_PENDING) {
      this.#state = AsyncTask.State.CANCEL_DELIVERED;
      return {
        code: ASYNC_EVENT_CODE.TASK_CANCELLED,
      };
    }
    
    const state = getOrCreateAsyncState(this.#componentIdx);
    const waitableSet = state.waitableSets.get(waitableSetRep);
    if (!waitableSet) { throw new Error('missing/invalid waitable set'); }
    
    waitableSet.numWaiting += 1;
    let event = null;
    
    while (event == null) {
      const awaitable = new Awaitable(waitableSet.getPendingEvent());
      const waited = await this.blockOn({ awaitable, isAsync, isCancellable: true });
      if (waited) {
        if (this.#state !== AsyncTask.State.INITIAL) {
          throw new Error('task should be in initial state found [' + this.#state + ']');
        }
        this.#state = AsyncTask.State.CANCELLED;
        return {
          code: ASYNC_EVENT_CODE.TASK_CANCELLED,
        };
      }
      
      event = waitableSet.poll();
    }
    
    waitableSet.numWaiting -= 1;
    return event;
  }
  
  waitForEventSync(opts) {
    throw new Error('AsyncTask#yieldSync() not implemented')
  }
  
  async pollForEvent(opts) {
    const { waitableSetRep, isAsync } = opts;
    _debugLog('[AsyncTask#pollForEvent()] args', { taskID: this.#id, waitableSetRep, isAsync });
    
    if (this.#isAsync !== isAsync) {
      throw new Error('async pollForEvent called on non-async task');
    }
    
    throw new Error('AsyncTask#pollForEvent() not implemented');
  }
  
  pollForEventSync(opts) {
    throw new Error('AsyncTask#yieldSync() not implemented')
  }
  
  async blockOn(opts) {
    const { awaitable, isCancellable, forCallback } = opts;
    _debugLog('[AsyncTask#blockOn()] args', { taskID: this.#id, awaitable, isCancellable, forCallback });
    
    if (awaitable.resolved() && !ASYNC_DETERMINISM && _coinFlip()) {
      return AsyncTask.BlockResult.NOT_CANCELLED;
    }
    
    const cstate = getOrCreateAsyncState(this.#componentIdx);
    if (forCallback) { cstate.exclusiveRelease(); }
    
    let cancelled = await this.onBlock(awaitable);
    if (cancelled === AsyncTask.BlockResult.CANCELLED && !isCancellable) {
      const secondCancel = await this.onBlock(awaitable);
      if (secondCancel !== AsyncTask.BlockResult.NOT_CANCELLED) {
        throw new Error('uncancellable task was canceled despite second onBlock()');
      }
    }
    
    if (forCallback) {
      const acquired = new Awaitable(cstate.exclusiveLock());
      cancelled = await this.onBlock(acquired);
      if (cancelled === AsyncTask.BlockResult.CANCELLED) {
        const secondCancel = await this.onBlock(acquired);
        if (secondCancel !== AsyncTask.BlockResult.NOT_CANCELLED) {
          throw new Error('uncancellable callback task was canceled despite second onBlock()');
        }
      }
    }
    
    if (cancelled === AsyncTask.BlockResult.CANCELLED) {
      if (this.#state !== AsyncTask.State.INITIAL) {
        throw new Error('cancelled task is not at initial state');
      }
      if (isCancellable) {
        this.#state = AsyncTask.State.CANCELLED;
        return AsyncTask.BlockResult.CANCELLED;
      } else {
        this.#state = AsyncTask.State.CANCEL_PENDING;
        return AsyncTask.BlockResult.NOT_CANCELLED;
      }
    }
    
    return AsyncTask.BlockResult.NOT_CANCELLED;
  }
  
  async onBlock(awaitable) {
    _debugLog('[AsyncTask#onBlock()] args', { taskID: this.#id, awaitable });
    if (!(awaitable instanceof Awaitable)) {
      throw new Error('invalid awaitable during onBlock');
    }
    
    // Build a promise that this task can await on which resolves when it is awoken
    const { promise, resolve, reject } = Promise.withResolvers();
    this.awaitableResume = () => {
      _debugLog('[AsyncTask] resuming after onBlock', { taskID: this.#id });
      resolve();
    };
    this.awaitableCancel = (err) => {
      _debugLog('[AsyncTask] rejecting after onBlock', { taskID: this.#id, err });
      reject(err);
    };
    
    // Park this task/execution to be handled later
    const state = getOrCreateAsyncState(this.#componentIdx);
    state.parkTaskOnAwaitable({ awaitable, task: this });
    
    try {
      await promise;
      return AsyncTask.BlockResult.NOT_CANCELLED;
    } catch (err) {
      // rejection means task cancellation
      return AsyncTask.BlockResult.CANCELLED;
    }
  }
  
  async asyncOnBlock(awaitable) {
    _debugLog('[AsyncTask#asyncOnBlock()] args', { taskID: this.#id, awaitable });
    if (!(awaitable instanceof Awaitable)) {
      throw new Error('invalid awaitable during onBlock');
    }
    // TODO: watch for waitable AND cancellation
    // TODO: if it WAS cancelled:
    // - return true
    // - only once per subtask
    // - do not wait on the scheduler
    // - control flow should go to the subtask (only once)
    // - Once subtask blocks/resolves, reqlinquishControl() will tehn resolve request_cancel_end (without scheduler lock release)
    // - control flow goes back to request_cancel
    //
    // Subtask cancellation should work similarly to an async import call -- runs sync up until
    // the subtask blocks or resolves
    //
    throw new Error('AsyncTask#asyncOnBlock() not yet implemented');
  }
  
  async yield(opts) {
    const { isCancellable, forCallback } = opts;
    _debugLog('[AsyncTask#yield()] args', { taskID: this.#id, isCancellable, forCallback });
    
    if (isCancellable && this.status === AsyncTask.State.CANCEL_PENDING) {
      this.#state = AsyncTask.State.CANCELLED;
      return {
        code: ASYNC_EVENT_CODE.TASK_CANCELLED,
        payload: [0, 0],
      };
    }
    
    // TODO: Awaitables need to *always* trigger the parking mechanism when they're done...?
    // TODO: Component async state should remember which awaitables are done and work to clear tasks waiting
    
    const blockResult = await this.blockOn({
      awaitable: new Awaitable(new Promise(resolve => setTimeout(resolve, 0))),
      isCancellable,
      forCallback,
    });
    
    if (blockResult === AsyncTask.BlockResult.CANCELLED) {
      if (this.#state !== AsyncTask.State.INITIAL) {
        throw new Error('task should be in initial state found [' + this.#state + ']');
      }
      this.#state = AsyncTask.State.CANCELLED;
      return {
        code: ASYNC_EVENT_CODE.TASK_CANCELLED,
        payload: [0, 0],
      };
    }
    
    return {
      code: ASYNC_EVENT_CODE.NONE,
      payload: [0, 0],
    };
  }
  
  yieldSync(opts) {
    throw new Error('AsyncTask#yieldSync() not implemented')
  }
  
  cancel() {
    _debugLog('[AsyncTask#cancel()] args', { });
    if (!this.taskState() !== AsyncTask.State.CANCEL_DELIVERED) {
      throw new Error('invalid task state for cancellation');
    }
    if (this.borrowedHandles.length > 0) { throw new Error('task still has borrow handles'); }
    
    this.#onResolve(new Error('cancelled'));
    this.#state = AsyncTask.State.RESOLVED;
  }
  
  resolve(results) {
    _debugLog('[AsyncTask#resolve()] args', { results });
    if (this.#state === AsyncTask.State.RESOLVED) {
      throw new Error('task is already resolved');
    }
    if (this.borrowedHandles.length > 0) { throw new Error('task still has borrow handles'); }
    this.#onResolve(results.length === 1 ? results[0] : results);
    this.#state = AsyncTask.State.RESOLVED;
  }
  
  exit() {
    _debugLog('[AsyncTask#exit()] args', { });
    
    // TODO: ensure there is only one task at a time (scheduler.lock() functionality)
    if (this.#state !== AsyncTask.State.RESOLVED) {
      throw new Error('task exited without resolution');
    }
    if (this.borrowedHandles > 0) {
      throw new Error('task exited without clearing borrowed handles');
    }
    
    const state = getOrCreateAsyncState(this.#componentIdx);
    if (!state) { throw new Error('missing async state for component [' + this.#componentIdx + ']'); }
    if (!this.#isAsync && !state.inSyncExportCall) {
      throw new Error('sync task must be run from components known to be in a sync export call');
    }
    state.inSyncExportCall = false;
    
    this.startPendingTask();
  }
  
  startPendingTask(args) {
    _debugLog('[AsyncTask#startPendingTask()] args', args);
    throw new Error('AsyncTask#startPendingTask() not implemented');
  }
  
  createSubtask(args) {
    _debugLog('[AsyncTask#createSubtask()] args', args);
    const newSubtask = new AsyncSubtask({
      componentIdx: this.componentIdx(),
      taskID: this.id(),
      memoryIdx: args?.memoryIdx,
    });
    this.#subtasks.push(newSubtask);
    return newSubtask;
  }
  
  currentSubtask() {
    _debugLog('[AsyncTask#currentSubtask()]');
    if (this.#subtasks.length === 0) { throw new Error('no current subtask'); }
    return this.#subtasks.at(-1);
  }
  
  endCurrentSubtask() {
    _debugLog('[AsyncTask#endCurrentSubtask()]');
    if (this.#subtasks.length === 0) { throw new Error('cannot end current subtask: no current subtask'); }
    const subtask = this.#subtasks.pop();
    subtask.drop();
    return subtask;
  }
}

function unpackCallbackResult(result) {
  _debugLog('[unpackCallbackResult()] args', { result });
  if (!(_typeCheckValidI32(result))) { throw new Error('invalid callback return value [' + result + '], not a valid i32'); }
  const eventCode = result & 0xF;
  if (eventCode < 0 || eventCode > 3) {
    throw new Error('invalid async return value [' + eventCode + '], outside callback code range');
  }
  if (result < 0 || result >= 2**32) { throw new Error('invalid callback result'); }
  // TODO: table max length check?
  const waitableSetIdx = result >> 4;
  return [eventCode, waitableSetIdx];
}
const ASYNC_STATE = new Map();

function getOrCreateAsyncState(componentIdx, init) {
  if (!ASYNC_STATE.has(componentIdx)) {
    ASYNC_STATE.set(componentIdx, new ComponentAsyncState());
  }
  return ASYNC_STATE.get(componentIdx);
}

class ComponentAsyncState {
  #callingAsyncImport = false;
  #syncImportWait = Promise.withResolvers();
  #lock = null;
  
  mayLeave = true;
  waitableSets = new RepTable();
  waitables = new RepTable();
  
  #parkedTasks = new Map();
  
  callingSyncImport(val) {
    if (val === undefined) { return this.#callingAsyncImport; }
    if (typeof val !== 'boolean') { throw new TypeError('invalid setting for async import'); }
    const prev = this.#callingAsyncImport;
    this.#callingAsyncImport = val;
    if (prev === true && this.#callingAsyncImport === false) {
      this.#notifySyncImportEnd();
    }
  }
  
  #notifySyncImportEnd() {
    const existing = this.#syncImportWait;
    this.#syncImportWait = Promise.withResolvers();
    existing.resolve();
  }
  
  async waitForSyncImportCallEnd() {
    await this.#syncImportWait.promise;
  }
  
  parkTaskOnAwaitable(args) {
    if (!args.awaitable) { throw new TypeError('missing awaitable when trying to park'); }
    if (!args.task) { throw new TypeError('missing task when trying to park'); }
    const { awaitable, task } = args;
    
    let taskList = this.#parkedTasks.get(awaitable.id());
    if (!taskList) {
      taskList = [];
      this.#parkedTasks.set(awaitable.id(), taskList);
    }
    taskList.push(task);
    
    this.wakeNextTaskForAwaitable(awaitable);
  }
  
  wakeNextTaskForAwaitable(awaitable) {
    if (!awaitable) { throw new TypeError('missing awaitable when waking next task'); }
    const awaitableID = awaitable.id();
    
    const taskList = this.#parkedTasks.get(awaitableID);
    if (!taskList || taskList.length === 0) {
      _debugLog('[ComponentAsyncState] no tasks waiting for awaitable', { awaitableID: awaitable.id() });
      return;
    }
    
    let task = taskList.shift(); // todo(perf)
    if (!task) { throw new Error('no task in parked list despite previous check'); }
    
    if (!task.awaitableResume) {
      throw new Error('task ready due to awaitable is missing resume', { taskID: task.id(), awaitableID });
    }
    task.awaitableResume();
  }
  
  async exclusiveLock() {  // TODO: use atomics
  if (this.#lock === null) {
    this.#lock = { ticket: 0n };
  }
  
  // Take a ticket for the next valid usage
  const ticket = ++this.#lock.ticket;
  
  _debugLog('[ComponentAsyncState#exclusiveLock()] locking', {
    currentTicket: ticket - 1n,
    ticket
  });
  
  // If there is an active promise, then wait for it
  let finishedTicket;
  while (this.#lock.promise) {
    finishedTicket = await this.#lock.promise;
    if (finishedTicket === ticket - 1n) { break; }
  }
  
  const { promise, resolve } = Promise.withResolvers();
  this.#lock = {
    ticket,
    promise,
    resolve,
  };
  
  return this.#lock.promise;
}

exclusiveRelease() {
  _debugLog('[ComponentAsyncState#exclusiveRelease()] releasing', {
    currentTicket: this.#lock === null ? 'none' : this.#lock.ticket,
  });
  
  if (this.#lock === null) { return; }
  
  const existingLock = this.#lock;
  this.#lock = null;
  existingLock.resolve(existingLock.ticket);
}

isExclusivelyLocked() { return this.#lock !== null; }

}

function prepareCall(memoryIdx) {
  _debugLog('[prepareCall()] args', { memoryIdx });
  
  const taskMeta = getCurrentTask(ASYNC_CURRENT_COMPONENT_IDXS.at(-1), ASYNC_CURRENT_TASK_IDS.at(-1));
  if (!taskMeta) { throw new Error('invalid/missing current async task meta during prepare call'); }
  
  const task = taskMeta.task;
  if (!task) { throw new Error('unexpectedly missing task in task meta during prepare call'); }
  
  const state = getOrCreateAsyncState(task.componentIdx());
  if (!state) {
    throw new Error('invalid/missing async state for component instance [' + componentInstanceID + ']');
  }
  
  const subtask = task.createSubtask({
    memoryIdx,
  });
  
}

function asyncStartCall(callbackIdx, postReturnIdx) {
  _debugLog('[asyncStartCall()] args', { callbackIdx, postReturnIdx });
  
  const taskMeta = getCurrentTask(ASYNC_CURRENT_COMPONENT_IDXS.at(-1), ASYNC_CURRENT_TASK_IDS.at(-1));
  if (!taskMeta) { throw new Error('invalid/missing current async task meta during prepare call'); }
  
  const task = taskMeta.task;
  if (!task) { throw new Error('unexpectedly missing task in task meta during prepare call'); }
  
  const subtask = task.currentSubtask();
  if (!subtask) { throw new Error('invalid/missing subtask during async start call'); }
  
  return Number(subtask.waitableRep()) << 4 | subtask.getStateNumber();
}

function syncStartCall(callbackIdx) {
  _debugLog('[syncStartCall()] args', { callbackIdx });
}

if (!Promise.withResolvers) {
  Promise.withResolvers = () => {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
      resolve = res;
      reject = rej;
    });
    return { promise, resolve, reject };
  };
}

const _debugLog = (...args) => {
  if (!globalThis?.process?.env?.JCO_DEBUG) { return; }
  console.debug(...args);
}
const ASYNC_DETERMINISM = 'random';
const _coinFlip = () => { return Math.random() > 0.5; };
const I32_MAX = 2_147_483_647;
const I32_MIN = -2_147_483_648;
const _typeCheckValidI32 = (n) => typeof n === 'number' && n >= I32_MIN && n <= I32_MAX;

const isNode = typeof process !== 'undefined' && process.versions && process.versions.node;
let _fs;
async function fetchCompile (url) {
  if (isNode) {
    _fs = _fs || await import('node:fs/promises');
    return WebAssembly.compile(await _fs.readFile(url));
  }
  return fetch(url).then(WebAssembly.compileStreaming);
}

class ComponentError extends Error {
  constructor (value) {
    const enumerable = typeof value !== 'string';
    super(enumerable ? `${String(value)} (see error.payload)` : value);
    Object.defineProperty(this, 'payload', { value, enumerable });
  }
}

class RepTable {
  #data = [0, null];
  
  insert(val) {
    _debugLog('[RepTable#insert()] args', { val });
    const freeIdx = this.#data[0];
    if (freeIdx === 0) {
      this.#data.push(val);
      this.#data.push(null);
      return (this.#data.length >> 1) - 1;
    }
    this.#data[0] = this.#data[freeIdx << 1];
    const placementIdx = freeIdx << 1;
    this.#data[placementIdx] = val;
    this.#data[placementIdx + 1] = null;
    return freeIdx;
  }
  
  get(rep) {
    _debugLog('[RepTable#get()] args', { rep });
    const baseIdx = rep << 1;
    const val = this.#data[baseIdx];
    return val;
  }
  
  contains(rep) {
    _debugLog('[RepTable#contains()] args', { rep });
    const baseIdx = rep << 1;
    return !!this.#data[baseIdx];
  }
  
  remove(rep) {
    _debugLog('[RepTable#remove()] args', { rep });
    if (this.#data.length === 2) { throw new Error('invalid'); }
    
    const baseIdx = rep << 1;
    const val = this.#data[baseIdx];
    if (val === 0) { throw new Error('invalid resource rep (cannot be 0)'); }
    
    this.#data[baseIdx] = this.#data[0];
    this.#data[0] = rep;
    
    return val;
  }
  
  clear() {
    _debugLog('[RepTable#clear()] args', { rep });
    this.#data = [0, null];
  }
}

function throwInvalidBool() {
  throw new TypeError('invalid variant discriminant for bool');
}

const instantiateCore = WebAssembly.instantiate;


let exports0;
let memory0;
let realloc0;
let primitivesEchoS32;

function echoS32(arg0) {
  _debugLog('[iface="local:types-test/primitives", function="echo-s32"][Instruction::CallWasm] enter', {
    funcName: 'echo-s32',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'primitivesEchoS32');
  const ret = primitivesEchoS32(toInt32(arg0));
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/primitives", function="echo-s32"][Instruction::Return]', {
    funcName: 'echo-s32',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let primitivesEchoS64;

function echoS64(arg0) {
  _debugLog('[iface="local:types-test/primitives", function="echo-s64"][Instruction::CallWasm] enter', {
    funcName: 'echo-s64',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'primitivesEchoS64');
  const ret = primitivesEchoS64(toInt64(arg0));
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/primitives", function="echo-s64"][Instruction::Return]', {
    funcName: 'echo-s64',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let primitivesEchoF32;

function echoF32(arg0) {
  _debugLog('[iface="local:types-test/primitives", function="echo-f32"][Instruction::CallWasm] enter', {
    funcName: 'echo-f32',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'primitivesEchoF32');
  const ret = primitivesEchoF32(+arg0);
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/primitives", function="echo-f32"][Instruction::Return]', {
    funcName: 'echo-f32',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let primitivesEchoF64;

function echoF64(arg0) {
  _debugLog('[iface="local:types-test/primitives", function="echo-f64"][Instruction::CallWasm] enter', {
    funcName: 'echo-f64',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'primitivesEchoF64');
  const ret = primitivesEchoF64(+arg0);
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/primitives", function="echo-f64"][Instruction::Return]', {
    funcName: 'echo-f64',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let primitivesEchoBool;

function echoBool(arg0) {
  _debugLog('[iface="local:types-test/primitives", function="echo-bool"][Instruction::CallWasm] enter', {
    funcName: 'echo-bool',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'primitivesEchoBool');
  const ret = primitivesEchoBool(arg0 ? 1 : 0);
  endCurrentTask(0);
  var bool0 = ret;
  _debugLog('[iface="local:types-test/primitives", function="echo-bool"][Instruction::Return]', {
    funcName: 'echo-bool',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return bool0 == 0 ? false : (bool0 == 1 ? true : throwInvalidBool());
}
let primitivesEchoString;

function echoString(arg0) {
  var ptr0 = utf8Encode(arg0, realloc0, memory0);
  var len0 = utf8EncodedLen;
  _debugLog('[iface="local:types-test/primitives", function="echo-string"][Instruction::CallWasm] enter', {
    funcName: 'echo-string',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'primitivesEchoString');
  const ret = primitivesEchoString(ptr0, len0);
  endCurrentTask(0);
  var ptr1 = dataView(memory0).getUint32(ret + 0, true);
  var len1 = dataView(memory0).getUint32(ret + 4, true);
  var result1 = utf8Decoder.decode(new Uint8Array(memory0.buffer, ptr1, len1));
  _debugLog('[iface="local:types-test/primitives", function="echo-string"][Instruction::Return]', {
    funcName: 'echo-string',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return result1;
}
let enumsEchoColor;

function echoColor(arg0) {
  var val0 = arg0;
  let enum0;
  switch (val0) {
    case 'red': {
      enum0 = 0;
      break;
    }
    case 'green': {
      enum0 = 1;
      break;
    }
    case 'blue': {
      enum0 = 2;
      break;
    }
    default: {
      if ((arg0) instanceof Error) {
        console.error(arg0);
      }
      
      throw new TypeError(`"${val0}" is not one of the cases of color`);
    }
  }
  _debugLog('[iface="local:types-test/enums", function="echo-color"][Instruction::CallWasm] enter', {
    funcName: 'echo-color',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'enumsEchoColor');
  const ret = enumsEchoColor(enum0);
  endCurrentTask(0);
  let enum1;
  switch (ret) {
    case 0: {
      enum1 = 'red';
      break;
    }
    case 1: {
      enum1 = 'green';
      break;
    }
    case 2: {
      enum1 = 'blue';
      break;
    }
    default: {
      throw new TypeError('invalid discriminant specified for Color');
    }
  }
  _debugLog('[iface="local:types-test/enums", function="echo-color"][Instruction::Return]', {
    funcName: 'echo-color',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return enum1;
}
let enumsColorName;

function colorName(arg0) {
  var val0 = arg0;
  let enum0;
  switch (val0) {
    case 'red': {
      enum0 = 0;
      break;
    }
    case 'green': {
      enum0 = 1;
      break;
    }
    case 'blue': {
      enum0 = 2;
      break;
    }
    default: {
      if ((arg0) instanceof Error) {
        console.error(arg0);
      }
      
      throw new TypeError(`"${val0}" is not one of the cases of color`);
    }
  }
  _debugLog('[iface="local:types-test/enums", function="color-name"][Instruction::CallWasm] enter', {
    funcName: 'color-name',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'enumsColorName');
  const ret = enumsColorName(enum0);
  endCurrentTask(0);
  var ptr1 = dataView(memory0).getUint32(ret + 0, true);
  var len1 = dataView(memory0).getUint32(ret + 4, true);
  var result1 = utf8Decoder.decode(new Uint8Array(memory0.buffer, ptr1, len1));
  _debugLog('[iface="local:types-test/enums", function="color-name"][Instruction::Return]', {
    funcName: 'color-name',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return result1;
}
let flagsTestEchoPermissions;

function echoPermissions(arg0) {
  let flags0 = 0;
  if (typeof arg0 === 'object' && arg0 !== null) {
    flags0 = Boolean(arg0.read) << 0 | Boolean(arg0.write) << 1 | Boolean(arg0.execute) << 2;
  } else if (arg0 !== null && arg0!== undefined) {
    throw new TypeError('only an object, undefined or null can be converted to flags');
  }
  _debugLog('[iface="local:types-test/flags-test", function="echo-permissions"][Instruction::CallWasm] enter', {
    funcName: 'echo-permissions',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'flagsTestEchoPermissions');
  const ret = flagsTestEchoPermissions(flags0);
  endCurrentTask(0);
  if ((ret & 4294967288) !== 0) {
    throw new TypeError('flags have extraneous bits set');
  }
  var flags1 = {
    read: Boolean(ret & 1),
    write: Boolean(ret & 2),
    execute: Boolean(ret & 4),
  };
  _debugLog('[iface="local:types-test/flags-test", function="echo-permissions"][Instruction::Return]', {
    funcName: 'echo-permissions',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return flags1;
}
let flagsTestHasRead;

function hasRead(arg0) {
  let flags0 = 0;
  if (typeof arg0 === 'object' && arg0 !== null) {
    flags0 = Boolean(arg0.read) << 0 | Boolean(arg0.write) << 1 | Boolean(arg0.execute) << 2;
  } else if (arg0 !== null && arg0!== undefined) {
    throw new TypeError('only an object, undefined or null can be converted to flags');
  }
  _debugLog('[iface="local:types-test/flags-test", function="has-read"][Instruction::CallWasm] enter', {
    funcName: 'has-read',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'flagsTestHasRead');
  const ret = flagsTestHasRead(flags0);
  endCurrentTask(0);
  var bool1 = ret;
  _debugLog('[iface="local:types-test/flags-test", function="has-read"][Instruction::Return]', {
    funcName: 'has-read',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return bool1 == 0 ? false : (bool1 == 1 ? true : throwInvalidBool());
}
let flagsTestHasWrite;

function hasWrite(arg0) {
  let flags0 = 0;
  if (typeof arg0 === 'object' && arg0 !== null) {
    flags0 = Boolean(arg0.read) << 0 | Boolean(arg0.write) << 1 | Boolean(arg0.execute) << 2;
  } else if (arg0 !== null && arg0!== undefined) {
    throw new TypeError('only an object, undefined or null can be converted to flags');
  }
  _debugLog('[iface="local:types-test/flags-test", function="has-write"][Instruction::CallWasm] enter', {
    funcName: 'has-write',
    paramCount: 1,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'flagsTestHasWrite');
  const ret = flagsTestHasWrite(flags0);
  endCurrentTask(0);
  var bool1 = ret;
  _debugLog('[iface="local:types-test/flags-test", function="has-write"][Instruction::Return]', {
    funcName: 'has-write',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return bool1 == 0 ? false : (bool1 == 1 ? true : throwInvalidBool());
}
let containersSumList;

function sumList(arg0) {
  var val0 = arg0;
  var len0 = val0.length;
  var ptr0 = realloc0(0, 0, 4, len0 * 4);
  var src0 = new Uint8Array(val0.buffer, val0.byteOffset, len0 * 4);
  (new Uint8Array(memory0.buffer, ptr0, len0 * 4)).set(src0);
  _debugLog('[iface="local:types-test/containers", function="sum-list"][Instruction::CallWasm] enter', {
    funcName: 'sum-list',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'containersSumList');
  const ret = containersSumList(ptr0, len0);
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/containers", function="sum-list"][Instruction::Return]', {
    funcName: 'sum-list',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let containersEchoListS64;

function echoListS64(arg0) {
  var val0 = arg0;
  var len0 = val0.length;
  var ptr0 = realloc0(0, 0, 8, len0 * 8);
  var src0 = new Uint8Array(val0.buffer, val0.byteOffset, len0 * 8);
  (new Uint8Array(memory0.buffer, ptr0, len0 * 8)).set(src0);
  _debugLog('[iface="local:types-test/containers", function="echo-list-s64"][Instruction::CallWasm] enter', {
    funcName: 'echo-list-s64',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'containersEchoListS64');
  const ret = containersEchoListS64(ptr0, len0);
  endCurrentTask(0);
  var ptr1 = dataView(memory0).getUint32(ret + 0, true);
  var len1 = dataView(memory0).getUint32(ret + 4, true);
  var result1 = new BigInt64Array(memory0.buffer.slice(ptr1, ptr1 + len1 * 8));
  _debugLog('[iface="local:types-test/containers", function="echo-list-s64"][Instruction::Return]', {
    funcName: 'echo-list-s64',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return result1;
}
let containersCountList;

function countList(arg0) {
  var vec1 = arg0;
  var len1 = vec1.length;
  var result1 = realloc0(0, 0, 4, len1 * 8);
  for (let i = 0; i < vec1.length; i++) {
    const e = vec1[i];
    const base = result1 + i * 8;var ptr0 = utf8Encode(e, realloc0, memory0);
    var len0 = utf8EncodedLen;
    dataView(memory0).setUint32(base + 4, len0, true);
    dataView(memory0).setUint32(base + 0, ptr0, true);
  }
  _debugLog('[iface="local:types-test/containers", function="count-list"][Instruction::CallWasm] enter', {
    funcName: 'count-list',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'containersCountList');
  const ret = containersCountList(result1, len1);
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/containers", function="count-list"][Instruction::Return]', {
    funcName: 'count-list',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let containersDivide;

function divide(arg0, arg1) {
  _debugLog('[iface="local:types-test/containers", function="divide"][Instruction::CallWasm] enter', {
    funcName: 'divide',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'containersDivide');
  const ret = containersDivide(toInt32(arg0), toInt32(arg1));
  endCurrentTask(0);
  let variant1;
  switch (dataView(memory0).getUint8(ret + 0, true)) {
    case 0: {
      variant1= {
        tag: 'ok',
        val: dataView(memory0).getInt32(ret + 4, true)
      };
      break;
    }
    case 1: {
      var ptr0 = dataView(memory0).getUint32(ret + 4, true);
      var len0 = dataView(memory0).getUint32(ret + 8, true);
      var result0 = utf8Decoder.decode(new Uint8Array(memory0.buffer, ptr0, len0));
      variant1= {
        tag: 'err',
        val: result0
      };
      break;
    }
    default: {
      throw new TypeError('invalid variant discriminant for expected');
    }
  }
  _debugLog('[iface="local:types-test/containers", function="divide"][Instruction::Return]', {
    funcName: 'divide',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  const retCopy = variant1;
  
  if (typeof retCopy === 'object' && retCopy.tag === 'err') {
    throw new ComponentError(retCopy.val);
  }
  return retCopy.val;
  
}
let multiParamsAdd2;

function add2(arg0, arg1) {
  _debugLog('[iface="local:types-test/multi-params", function="add2"][Instruction::CallWasm] enter', {
    funcName: 'add2',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'multiParamsAdd2');
  const ret = multiParamsAdd2(toInt32(arg0), toInt32(arg1));
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/multi-params", function="add2"][Instruction::Return]', {
    funcName: 'add2',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let multiParamsAdd3;

function add3(arg0, arg1, arg2) {
  _debugLog('[iface="local:types-test/multi-params", function="add3"][Instruction::CallWasm] enter', {
    funcName: 'add3',
    paramCount: 3,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'multiParamsAdd3');
  const ret = multiParamsAdd3(toInt32(arg0), toInt32(arg1), toInt32(arg2));
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/multi-params", function="add3"][Instruction::Return]', {
    funcName: 'add3',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let multiParamsAdd4;

function add4(arg0, arg1, arg2, arg3) {
  _debugLog('[iface="local:types-test/multi-params", function="add4"][Instruction::CallWasm] enter', {
    funcName: 'add4',
    paramCount: 4,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'multiParamsAdd4');
  const ret = multiParamsAdd4(toInt32(arg0), toInt32(arg1), toInt32(arg2), toInt32(arg3));
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/multi-params", function="add4"][Instruction::Return]', {
    funcName: 'add4',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return ret;
}
let multiParamsConcat3;

function concat3(arg0, arg1, arg2) {
  var ptr0 = utf8Encode(arg0, realloc0, memory0);
  var len0 = utf8EncodedLen;
  var ptr1 = utf8Encode(arg1, realloc0, memory0);
  var len1 = utf8EncodedLen;
  var ptr2 = utf8Encode(arg2, realloc0, memory0);
  var len2 = utf8EncodedLen;
  _debugLog('[iface="local:types-test/multi-params", function="concat3"][Instruction::CallWasm] enter', {
    funcName: 'concat3',
    paramCount: 6,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'multiParamsConcat3');
  const ret = multiParamsConcat3(ptr0, len0, ptr1, len1, ptr2, len2);
  endCurrentTask(0);
  var ptr3 = dataView(memory0).getUint32(ret + 0, true);
  var len3 = dataView(memory0).getUint32(ret + 4, true);
  var result3 = utf8Decoder.decode(new Uint8Array(memory0.buffer, ptr3, len3));
  _debugLog('[iface="local:types-test/multi-params", function="concat3"][Instruction::Return]', {
    funcName: 'concat3',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return result3;
}
let multiParamsMixedParams;

function mixedParams(arg0, arg1, arg2) {
  var ptr0 = utf8Encode(arg1, realloc0, memory0);
  var len0 = utf8EncodedLen;
  _debugLog('[iface="local:types-test/multi-params", function="mixed-params"][Instruction::CallWasm] enter', {
    funcName: 'mixed-params',
    paramCount: 4,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'multiParamsMixedParams');
  const ret = multiParamsMixedParams(toInt32(arg0), ptr0, len0, arg2 ? 1 : 0);
  endCurrentTask(0);
  var ptr1 = dataView(memory0).getUint32(ret + 0, true);
  var len1 = dataView(memory0).getUint32(ret + 4, true);
  var result1 = utf8Decoder.decode(new Uint8Array(memory0.buffer, ptr1, len1));
  _debugLog('[iface="local:types-test/multi-params", function="mixed-params"][Instruction::Return]', {
    funcName: 'mixed-params',
    paramCount: 1,
    async: false,
    postReturn: false
  });
  return result1;
}
let sideEffectsNoReturn;

function noReturn(arg0) {
  var ptr0 = utf8Encode(arg0, realloc0, memory0);
  var len0 = utf8EncodedLen;
  _debugLog('[iface="local:types-test/side-effects", function="no-return"][Instruction::CallWasm] enter', {
    funcName: 'no-return',
    paramCount: 2,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'sideEffectsNoReturn');
  sideEffectsNoReturn(ptr0, len0);
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/side-effects", function="no-return"][Instruction::Return]', {
    funcName: 'no-return',
    paramCount: 0,
    async: false,
    postReturn: false
  });
}
let sideEffectsNoParamsNoReturn;

function noParamsNoReturn() {
  _debugLog('[iface="local:types-test/side-effects", function="no-params-no-return"][Instruction::CallWasm] enter', {
    funcName: 'no-params-no-return',
    paramCount: 0,
    async: false,
    postReturn: false,
  });
  const _wasm_call_currentTaskID = startCurrentTask(0, false, 'sideEffectsNoParamsNoReturn');
  sideEffectsNoParamsNoReturn();
  endCurrentTask(0);
  _debugLog('[iface="local:types-test/side-effects", function="no-params-no-return"][Instruction::Return]', {
    funcName: 'no-params-no-return',
    paramCount: 0,
    async: false,
    postReturn: false
  });
}

const $init = (() => {
  let gen = (function* _initGenerator () {
    const module0 = fetchCompile(new URL('./types-test.core.wasm', import.meta.url));
    ({ exports: exports0 } = yield instantiateCore(yield module0));
    memory0 = exports0.memory;
    realloc0 = exports0.cabi_realloc;
    primitivesEchoS32 = exports0['local:types-test/primitives#echo-s32'];
    primitivesEchoS64 = exports0['local:types-test/primitives#echo-s64'];
    primitivesEchoF32 = exports0['local:types-test/primitives#echo-f32'];
    primitivesEchoF64 = exports0['local:types-test/primitives#echo-f64'];
    primitivesEchoBool = exports0['local:types-test/primitives#echo-bool'];
    primitivesEchoString = exports0['local:types-test/primitives#echo-string'];
    enumsEchoColor = exports0['local:types-test/enums#echo-color'];
    enumsColorName = exports0['local:types-test/enums#color-name'];
    flagsTestEchoPermissions = exports0['local:types-test/flags-test#echo-permissions'];
    flagsTestHasRead = exports0['local:types-test/flags-test#has-read'];
    flagsTestHasWrite = exports0['local:types-test/flags-test#has-write'];
    containersSumList = exports0['local:types-test/containers#sum-list'];
    containersEchoListS64 = exports0['local:types-test/containers#echo-list-s64'];
    containersCountList = exports0['local:types-test/containers#count-list'];
    containersDivide = exports0['local:types-test/containers#divide'];
    multiParamsAdd2 = exports0['local:types-test/multi-params#add2'];
    multiParamsAdd3 = exports0['local:types-test/multi-params#add3'];
    multiParamsAdd4 = exports0['local:types-test/multi-params#add4'];
    multiParamsConcat3 = exports0['local:types-test/multi-params#concat3'];
    multiParamsMixedParams = exports0['local:types-test/multi-params#mixed-params'];
    sideEffectsNoReturn = exports0['local:types-test/side-effects#no-return'];
    sideEffectsNoParamsNoReturn = exports0['local:types-test/side-effects#no-params-no-return'];
  })();
  let promise, resolve, reject;
  function runNext (value) {
    try {
      let done;
      do {
        ({ value, done } = gen.next(value));
      } while (!(value instanceof Promise) && !done);
      if (done) {
        if (resolve) resolve(value);
        else return value;
      }
      if (!promise) promise = new Promise((_resolve, _reject) => (resolve = _resolve, reject = _reject));
      value.then(runNext, reject);
    }
    catch (e) {
      if (reject) reject(e);
      else throw e;
    }
  }
  const maybeSyncReturn = runNext(null);
  return promise || maybeSyncReturn;
})();

await $init;
const containers = {
  countList: countList,
  divide: divide,
  echoListS64: echoListS64,
  sumList: sumList,
  
};
const enums = {
  colorName: colorName,
  echoColor: echoColor,
  
};
const flagsTest = {
  echoPermissions: echoPermissions,
  hasRead: hasRead,
  hasWrite: hasWrite,
  
};
const multiParams = {
  add2: add2,
  add3: add3,
  add4: add4,
  concat3: concat3,
  mixedParams: mixedParams,
  
};
const primitives = {
  echoBool: echoBool,
  echoF32: echoF32,
  echoF64: echoF64,
  echoS32: echoS32,
  echoS64: echoS64,
  echoString: echoString,
  
};
const sideEffects = {
  noParamsNoReturn: noParamsNoReturn,
  noReturn: noReturn,
  
};

export { containers, enums, flagsTest, multiParams, primitives, sideEffects, containers as 'local:types-test/containers', enums as 'local:types-test/enums', flagsTest as 'local:types-test/flags-test', multiParams as 'local:types-test/multi-params', primitives as 'local:types-test/primitives', sideEffects as 'local:types-test/side-effects',  }