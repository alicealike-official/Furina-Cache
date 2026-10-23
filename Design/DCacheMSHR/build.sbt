name := "Furina-MSHR-DCache"

version := "1.0"

scalaVersion := "2.11.12"

libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % "1.10.2",
  "com.github.spinalhdl" %% "spinalhdl-lib"  % "1.10.2",
  "com.github.spinalhdl" %% "spinalhdl-sim"  % "1.10.2",
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % "1.10.2")
)

fork := true

// 默认 `sbt run` 生成 Verilog；仿真用 runMain 显式指定
Compile / mainClass := Some("furina.dcache.DCacheVerilog")

scalacOptions ++= Seq("-deprecation", "-feature")
