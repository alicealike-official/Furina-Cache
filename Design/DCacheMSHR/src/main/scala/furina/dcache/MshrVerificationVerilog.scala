package furina.dcache

import spinal.core._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

/** 从同一配置生成 MSHR RTL 与 SV 参数；复位统一为异步低有效。 */
object MshrVerificationVerilog extends App {
    val output = if (args.nonEmpty) args(0) else "../../verif_mshr/generated/mshr"
    val entries = if (args.length > 1) args(1).toInt else 4
    val slots = if (args.length > 2) args(2).toInt else 4
    val cfg = CacheConfig(MSHR_ENTRIES = entries, MSHR_MAX_PENDING = slots)
    Files.createDirectories(Paths.get(output))
    SpinalConfig(
        targetDirectory = output,
        withTimescale = false,
        defaultConfigForClockDomains = ClockDomainConfig(
            clockEdge = RISING,
            resetKind = ASYNC,
            resetActiveLevel = LOW
        )
    ).generateVerilog(new Mshr(cfg))

    val parameters = Seq(
        "ADDR_WIDTH" -> cfg.ADDR_WIDTH,
        "DATA_WIDTH" -> cfg.DATA_WIDTH,
        "BLOCK_SIZE" -> cfg.BLOCK_SIZE,
        "LINE_WIDTH" -> cfg.lineWidth,
        "WORDS_PER_BLOCK" -> cfg.wordsPerBlock,
        "NUM_SETS" -> cfg.NUM_SETS,
        "NUM_WAYS" -> cfg.NUM_WAYS,
        "MSHR_ENTRIES" -> cfg.MSHR_ENTRIES,
        "MSHR_MAX_PENDING" -> cfg.MSHR_MAX_PENDING,
        "TAG_WIDTH" -> cfg.tagWidth,
        "INDEX_WIDTH" -> cfg.indexWidth,
        "WAY_WIDTH" -> cfg.wayWidth,
        "WORD_OFF_WIDTH" -> cfg.wordOffWidth,
        "ENTRY_WIDTH" -> cfg.mshrIdWidth,
        "SLOT_WIDTH" -> (log2Up(cfg.MSHR_MAX_PENDING) max 1),
        "CPU_ID_WIDTH" -> cfg.ID_WIDTH,
        "BUS_ID_WIDTH" -> cfg.busIdWidth,
        "WBB_ENTRIES" -> cfg.WBB_ENTRIES,
        "WBB_SLOT_WIDTH" -> cfg.wbbIdWidth,
        "LOCK_WIDTH" -> (cfg.NUM_SETS * cfg.NUM_WAYS)
    )
    val content = "// Generated together with Mshr.v; do not edit independently.\n" +
        "package mshr_params_pkg;\n" + parameters.map { case (name, value) =>
            s"    parameter int $name = $value;\n"
        }.mkString + "endpackage\n"
    Files.write(Paths.get(output, "mshr_params_pkg.sv"), content.getBytes(StandardCharsets.UTF_8))
}
