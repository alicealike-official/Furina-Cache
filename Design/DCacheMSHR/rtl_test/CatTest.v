// Generator : SpinalHDL v1.10.2    git head : 279867b771fb50fc0aec21d8a20d8fdad0f87e3f
// Component : CatTest
// Git hash  : 17e6a5e7a95e3005eaaafc604d6c361ab326604e

`timescale 1ns/1ps

module CatTest (
  output wire [7:0]    io_b,
  output wire [7:0]    io_c,
  output wire [7:0]    io_d
);

  wire       [1:0]    vec_0;
  wire       [1:0]    vec_1;
  wire       [1:0]    vec_2;
  wire       [1:0]    vec_3;

  assign vec_0 = 2'b00;
  assign vec_1 = 2'b01;
  assign vec_2 = 2'b10;
  assign vec_3 = 2'b11;
  assign io_b = {vec_3,{vec_2,{vec_1,vec_0}}};
  assign io_c = {vec_0,{vec_1,{vec_2,vec_3}}};
  assign io_d = {2'b00,{2'b01,{2'b10,2'b11}}};

endmodule
