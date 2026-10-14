name := "Furina Cache"

version := "1.0"

scalaVersion := "2.11.12"

libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % "1.10.2",
  "com.github.spinalhdl" %% "spinalhdl-lib"  % "1.10.2",
  "com.github.spinalhdl" %% "spinalhdl-sim"  % "1.10.2",
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % "1.10.2")
)

fork := true

Compile / scalaSource := baseDirectory.value / "Design" / "Cache" / "spinal"

Test / scalaSource := baseDirectory.value / "test" / "scala"