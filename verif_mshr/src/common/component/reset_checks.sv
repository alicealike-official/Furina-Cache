// 三套环境共用的复位结果记录；每项都检查DUT状态或实际接口事件，错误不因再次复位清零。
class reset_checks extends uvm_object;
    int checks;
    int failures;
    int stages[string];
    `uvm_object_utils(reset_checks)
    function new(string name = "reset_checks");
        super.new(name);
    endfunction
    // 保存本项实际检查结果，失败立即报告，后续检查仍继续执行。
    function void check_condition(bit condition, string description);
        checks++;
        if (!condition) begin
            failures++;
            `error(description, "RESET_STATE")
        end
    endfunction
    // 对实际事件数量统一比较，避免三个test重复实现通过条件。
    function void check_count(string label, longint actual, longint expected);
        check_condition(actual == expected, $sformatf("%s actual=%0d expected=%0d", label, actual, expected));
    endfunction
    // 仅在该阶段的复位及恢复检查结束后记录，配合错误计数保留实际场景证据。
    function void mark_stage(string label);
        if (!stages.exists(label)) stages[label] = 0;
        stages[label]++;
        `info($sformatf("stage=%s count=%0d", label, stages[label]), "RESET_STAGE_COVERAGE")
    endfunction
    // 每套case结束时输出可审查计数，回归不只依赖sequence执行到末尾。
    function void report(string module_name, int reset_count);
        `info($sformatf("module=%s resets=%0d checks=%0d failures=%0d", module_name,
            reset_count, checks, failures), "RESET_COVERAGE")
    endfunction
endclass
