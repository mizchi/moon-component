ThisBuild / scalaVersion := "3.3.4"
ThisBuild / version := "0.1.0"

lazy val root = (project in file("."))
  .settings(
    name := "scala-host",
    libraryDependencies ++= Seq(
      "com.dylibso.chicory" % "runtime" % "1.0.0",
      "com.dylibso.chicory" % "wasm" % "1.0.0"
    )
  )
