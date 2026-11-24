// 配置并启动random场景；激励生成在sequence，数据/计数检查复用scenario test。
class mshr_random_test extends mshr_scenario_test;
    `uvm_component_utils(mshr_random_test)

    function new(string name = "mshr_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual task run_sequence();
endclass

// 运行独立场景并调用公共检查，避免在每个test重复实现结果判定。
task mshr_random_test::run_sequence();
    mshr_random_sequence seq;

    seq = mshr_random_sequence::type_id::create("seq");
    run_scenario(seq);
endtask
