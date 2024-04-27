module LFSR #(parameter Width = 4, parameter type TYPE=logic [Width-1:0]) (
    input logic [Width-1:0] seed, 
    input logic clk, 
    input logic load, 
    input logic enable, 
    output logic [Width-1:0] data_out);
    logic [Width-1] lead_bit;

    // always_comb
    //     case(Width)
    //         // 2: 
    //         4: lead_bit = data_out[6]^data_out[5];
    //         7: lead_bit = data_out[6]^data_out[5]^data_out[3]^data_out[0];
    //         // 8: 
    //         // 16: 
    //         // 32: 
    //         // 64: 
    //         // 128: 
    //         default: lead_bit = 1'bx;
    //     endcase

    //mux2 #(4) m1({data_out[3]^data_out[0], data_out[3:1]}, seed, select, m2f);
    // assign lead_bit = data_out[6]^data_out[5]^data_out[3]^data_out[0];
    flopenl #(7) f1(clk, load, enable, {lead_bit, data_out[Width-1:1]}, seed, data_out);

endmodule


