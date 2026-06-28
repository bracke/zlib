with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.Bits;
with Zlib.Huffman;

package body Zlib_Huffman_Tests is
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Huffman");
   end Name;

   procedure Test_Single_One_Bit_Code (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Lengths : constant Zlib.Huffman.Code_Length_Array :=
        [0 => 1];

      Table  : Zlib.Huffman.Decode_Table;
      Data   : constant Zlib.Byte_Array := [1 => 2#0000_0000#];
      R      : Zlib.Bits.Bit_Reader;
      Status : Zlib.Status_Code;
      Symbol : Zlib.Huffman.Symbol_Value;
   begin
      Zlib.Huffman.Build (Lengths, Table, Status);

      Assert
        (Status = Zlib.Ok,
         "single-symbol Huffman table must build successfully");

      Zlib.Bits.Init (R, Data);

      Symbol := Zlib.Huffman.Decode (R, Table, Status);

      Assert
        (Status = Zlib.Ok,
         "single-symbol Huffman code must decode successfully");

      Assert
        (Symbol = 0,
         "single-symbol Huffman code must decode symbol 0");
   end Test_Single_One_Bit_Code;

   procedure Test_Two_One_Bit_Codes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Lengths : constant Zlib.Huffman.Code_Length_Array :=
        [0 => 1,
         1 => 1];

      Table : Zlib.Huffman.Decode_Table;
      Data  : constant Zlib.Byte_Array := [1 => 2#0000_0010#];

      R       : Zlib.Bits.Bit_Reader;
      Status  : Zlib.Status_Code;
      Symbol0 : Zlib.Huffman.Symbol_Value;
      Symbol1 : Zlib.Huffman.Symbol_Value;
   begin
      Zlib.Huffman.Build (Lengths, Table, Status);

      Assert
        (Status = Zlib.Ok,
         "two-symbol Huffman table must build successfully");

      Zlib.Bits.Init (R, Data);

      Symbol0 := Zlib.Huffman.Decode (R, Table, Status);

      Assert
        (Status = Zlib.Ok,
         "first one-bit Huffman code must decode successfully");

      Assert
        (Symbol0 = 0,
         "first code bit 0 must decode symbol 0");

      Symbol1 := Zlib.Huffman.Decode (R, Table, Status);

      Assert
        (Status = Zlib.Ok,
         "second one-bit Huffman code must decode successfully");

      Assert
        (Symbol1 = 1,
         "second code bit 1 must decode symbol 1");
   end Test_Two_One_Bit_Codes;

   procedure Test_Invalid_Code_Is_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Lengths : constant Zlib.Huffman.Code_Length_Array :=
        [0 => 1];

      Table  : Zlib.Huffman.Decode_Table;
      Data : constant Zlib.Byte_Array :=
         [1 => 2#0000_0001#,   2 => 2#0000_0000#];
      R      : Zlib.Bits.Bit_Reader;
      Status : Zlib.Status_Code;
      Symbol : Zlib.Huffman.Symbol_Value;
      pragma Unreferenced (Symbol);
   begin
      Zlib.Huffman.Build (Lengths, Table, Status);

      Assert
        (Status = Zlib.Ok,
         "single-code Huffman table must build successfully");

      Zlib.Bits.Init (R, Data);

      Symbol := Zlib.Huffman.Decode (R, Table, Status);

      Assert
        (Status = Zlib.Invalid_Huffman_Code,
         "missing Huffman code must return Invalid_Huffman_Code");
   end Test_Invalid_Code_Is_Rejected;

   procedure Test_Oversubscribed_Tree_Is_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Lengths : constant Zlib.Huffman.Code_Length_Array :=
        [0 => 1,
         1 => 1,
         2 => 1];

      Table  : Zlib.Huffman.Decode_Table;
      Status : Zlib.Status_Code;
   begin
      Zlib.Huffman.Build (Lengths, Table, Status);

      Assert
        (Status = Zlib.Invalid_Huffman_Code,
         "three one-bit Huffman codes must be rejected as oversubscribed");
   end Test_Oversubscribed_Tree_Is_Rejected;

   procedure Test_Empty_Tree_Is_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Lengths : constant Zlib.Huffman.Code_Length_Array :=
        [0 => 0,
         1 => 0,
         2 => 0];

      Table  : Zlib.Huffman.Decode_Table;
      Status : Zlib.Status_Code;
   begin
      Zlib.Huffman.Build (Lengths, Table, Status);

      Assert
        (Status = Zlib.Invalid_Huffman_Code,
         "empty Huffman tree must be rejected");
   end Test_Empty_Tree_Is_Rejected;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Single_One_Bit_Code'Access,
         "Decode single one-bit Huffman code");

      Registration.Register_Routine
        (T, Test_Two_One_Bit_Codes'Access,
         "Decode two one-bit Huffman codes");

      Registration.Register_Routine
        (T, Test_Invalid_Code_Is_Rejected'Access,
         "Reject missing Huffman code");

      Registration.Register_Routine
        (T, Test_Oversubscribed_Tree_Is_Rejected'Access,
         "Reject oversubscribed Huffman tree");

      Registration.Register_Routine
        (T, Test_Empty_Tree_Is_Rejected'Access,
         "Reject empty Huffman tree");
   end Register_Tests;

end Zlib_Huffman_Tests;
