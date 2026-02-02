/** @module Interface local:types-test/flags-test **/
export function echoPermissions(p: Permissions): Permissions;
export function hasRead(p: Permissions): boolean;
export function hasWrite(p: Permissions): boolean;
export interface Permissions {
  read?: boolean,
  write?: boolean,
  execute?: boolean,
}
