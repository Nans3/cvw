module LFSR #(parameter Width = 4) (
    input logic [Width-1:0] seed, 
    input logic clk, 
    input logic load, 
    input logic enable, 
    output logic [Width-1:0] data_out);
    logic lead_bit;

    // if(Width == 3) begin
        // assign lead_bit = data_out[2]^data_out[0];
    // end
    // else if(Width == 4) begin
        // assign lead_bit = data_out[3]^data_out[0];
    // end
    // 00011101
    // else if(Width == 5) begin
        // assign lead_bit = data_out[4]^data_out[3]^data_out[2]^data_out[0];
    // // end
// 
   // 001101
    // else if(Width == 6) begin
    // assign lead_bit = data_out[5]^data_out[3];
    // // end
// 
// 
//    01101001
    // else if(Width == 7) begin
        // assign lead_bit = data_out[6]^data_out[5]^data_out[3]^data_out[0];
    // // end
// 
  //10100110
    // else if(Width == 8) begin
    // assign lead_bit = data_out[7]^data_out[5]^data_out[2]^data_out[1];
    // // end
// 
// 
//    000101111100
    // else if(Width == 9) begin
    // assign lead_bit = data_out[8]^data_out[7]^data_out[6]^data_out[4];
    // end

    
    if(Width == 3) begin
        assign lead_bit = data_out[2]^data_out[0];
    end
    else if(Width == 4) begin
        assign lead_bit = data_out[3]^data_out[0];
    end
    //00011101
    else if(Width == 5) begin
        assign lead_bit = data_out[4]^data_out[3]^data_out[2]^data_out[0];
    end

    //00110110
    else if(Width == 6) begin
        assign lead_bit = data_out[5]^data_out[4]^data_out[2]^data_out[1];
    end

    //01101001
    else if(Width == 7) begin
        assign lead_bit = data_out[6]^data_out[5]^data_out[3]^data_out[0];
    end

   // 10100110
    else if(Width == 8) begin
        assign lead_bit = data_out[7]^data_out[5]^data_out[2]^data_out[1];
    end

   // 000101111100
    else if(Width == 9) begin
        assign lead_bit = data_out[8]^data_out[6]^data_out[5]^data_out[4]^data_out[3]^data_out[2];
    end
    
    flopenl #(Width) f1(clk, load, enable, {data_out[Width-2:0], lead_bit}, seed, data_out);

endmodule


