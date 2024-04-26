module LFSR (
    input logic [3:0] seed, 
    input logic clk, 
    input logic load, 
    input logic enable, 
    input logic select, 
    output logic [3:0] data_out);


    //mux2 #(4) m1({data_out[3]^data_out[0], data_out[3:1]}, seed, select, m2f);
    flopenl #(4) f1(clk, load, enable, {data_out[3]^data_out[0], data_out[3:1]}, seed, data_out);



endmodule