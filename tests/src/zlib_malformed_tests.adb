with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Malformed_Tests is
   use type Zlib.Status_Code;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib malformed input");
   end Name;

   procedure Test_Unsupported_Method
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#79#,
         2 => 16#00#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#00#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Unsupported_Method,
         "non-Deflate zlib compression method must return Unsupported_Method");
   end Test_Unsupported_Method;

   procedure Test_Invalid_Header_Check
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#02#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#00#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Header,
         "bad zlib FCHECK bits must return Invalid_Header");
   end Test_Invalid_Header_Check;

   procedure Test_Preset_Dictionary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#20#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#00#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Unsupported_Preset_Dictionary,
         "FDICT zlib streams must return Unsupported_Preset_Dictionary");
   end Test_Preset_Dictionary;

   procedure Test_Invalid_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1  => 16#78#,
         2  => 16#01#,
         3  => 16#01#,
         4  => 16#05#,
         5  => 16#00#,
         6  => 16#FA#,
         7  => 16#FF#,
         8  => Zlib.Byte (Character'Pos ('h')),
         9  => Zlib.Byte (Character'Pos ('e')),
         10 => Zlib.Byte (Character'Pos ('l')),
         11 => Zlib.Byte (Character'Pos ('l')),
         12 => Zlib.Byte (Character'Pos ('o')),
         13 => 16#00#,
         14 => 16#00#,
         15 => 16#00#,
         16 => 16#01#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Checksum,
         "wrong Adler-32 must return Invalid_Checksum");
   end Test_Invalid_Checksum;

   procedure Test_Invalid_Stored_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1  => 16#78#,
         2  => 16#01#,
         3  => 16#01#,
         4  => 16#05#,
         5  => 16#00#,
         6  => 16#00#,
         7  => 16#00#,
         8  => Zlib.Byte (Character'Pos ('h')),
         9  => Zlib.Byte (Character'Pos ('e')),
         10 => Zlib.Byte (Character'Pos ('l')),
         11 => Zlib.Byte (Character'Pos ('l')),
         12 => Zlib.Byte (Character'Pos ('o')),
         13 => 16#06#,
         14 => 16#2C#,
         15 => 16#02#,
         16 => 16#15#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Stored_Block,
         "LEN/NLEN mismatch must return Invalid_Stored_Block");
   end Test_Invalid_Stored_Block;

   procedure Test_Invalid_Block_Type
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#01#,
         3 => 2#0000_0111#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#00#,
         7 => 16#01#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Block_Type,
         "BTYPE = 11 must return Invalid_Block_Type");
   end Test_Invalid_Block_Type;

   procedure Test_Truncated_Input (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#01#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Unexpected_End_Of_Input,
         "truncated zlib stream must return Unexpected_End_Of_Input");
   end Test_Truncated_Input;

   procedure Test_Invalid_Huffman_Code
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#01#,
         3 => 16#1B#,
         4 => 16#03#,
         5 => 16#00#,
         6 => 16#00#,
         7 => 16#00#,
         8 => 16#01#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Huffman_Code,
         "reserved fixed-Huffman length symbol must return Invalid_Huffman_Code");
   end Test_Invalid_Huffman_Code;

   procedure Test_Invalid_Distance
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#01#,
         3 => 16#03#,
         4 => 16#02#,
         5 => 16#00#,
         6 => 16#00#,
         7 => 16#00#,
         8 => 16#01#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Distance,
         "distance before output data must return Invalid_Distance");
   end Test_Invalid_Distance;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Unsupported_Method'Access,
         "Inflate rejects unsupported zlib method");

      Registration.Register_Routine
        (T,
         Test_Invalid_Header_Check'Access,
         "Inflate rejects invalid zlib header check");

      Registration.Register_Routine
        (T,
         Test_Preset_Dictionary'Access,
         "Inflate rejects preset dictionary streams");

      Registration.Register_Routine
        (T, Test_Invalid_Checksum'Access, "Inflate rejects invalid Adler-32");

      Registration.Register_Routine
        (T,
         Test_Invalid_Stored_Block'Access,
         "Inflate rejects invalid stored block");

      Registration.Register_Routine
        (T,
         Test_Invalid_Block_Type'Access,
         "Inflate rejects invalid Deflate block type");

      Registration.Register_Routine
        (T, Test_Truncated_Input'Access, "Inflate rejects truncated input");

      Registration.Register_Routine
        (T,
         Test_Invalid_Huffman_Code'Access,
         "Inflate rejects invalid Huffman symbol");

      Registration.Register_Routine
        (T,
         Test_Invalid_Distance'Access,
         "Inflate rejects invalid LZ77 distance");

   end Register_Tests;

end Zlib_Malformed_Tests;
