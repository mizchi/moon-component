(component
  (core module $m
    (func (export "run"))
  )
  (export "dep" (core module $m))
)
