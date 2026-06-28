with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.Bits;

package body Zlib_Bits_Tests is
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Bits");
   end Name;
   procedure Test_Read_Single_Bits_Lsb_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Data   : constant Zlib.Byte_Array := [1 => 2#1010_0101#];
      R      : Zlib.Bits.Bit_Reader;
      Status : Zlib.Status_Code;
   begin
      Zlib.Bits.Init (R, Data);

      Assert (Zlib.Bits.Read_Bit (R, Status), "bit 0 must be 1");
      Assert (Status = Zlib.Ok, "status after bit 0 must be Ok");

      Assert (not Zlib.Bits.Read_Bit (R, Status), "bit 1 must be 0");
      Assert (Status = Zlib.Ok, "status after bit 1 must be Ok");

      Assert (Zlib.Bits.Read_Bit (R, Status), "bit 2 must be 1");
      Assert (Status = Zlib.Ok, "status after bit 2 must be Ok");

      Assert (not Zlib.Bits.Read_Bit (R, Status), "bit 3 must be 0");
      Assert (Status = Zlib.Ok, "status after bit 3 must be Ok");
   end Test_Read_Single_Bits_Lsb_First;

   procedure Test_Read_Bits_Crosses_Byte_Boundary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1 => 2#1111_0000#,
         2 => 2#0000_1010#];

      R      : Zlib.Bits.Bit_Reader;
      Status : Zlib.Status_Code;
      Value  : Natural;
   begin
      Zlib.Bits.Init (R, Data);

      Value := Zlib.Bits.Read_Bits (R, 12, Status);

      Assert
        (Status = Zlib.Ok,
         "reading 12 bits must succeed");

      Assert
        (Value = 16#AF0#,
         "reading 12 LSB-first bits from 0xF0 0x0A must produce 0xAF0");
   end Test_Read_Bits_Crosses_Byte_Boundary;

   procedure Test_Align_To_Byte (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array :=
        [1 => 2#1111_1111#,
         2 => 2#0000_0001#];

      R      : Zlib.Bits.Bit_Reader;
      Status : Zlib.Status_Code;
      Value  : Natural;
   begin
      Zlib.Bits.Init (R, Data);

      Value := Zlib.Bits.Read_Bits (R, 3, Status);

      Assert
        (Status = Zlib.Ok,
         "initial 3-bit read must succeed");

      Assert
        (Value = 7,
         "first three bits must be 7");

      Zlib.Bits.Align_To_Byte (R);

      Value := Zlib.Bits.Read_Bits (R, 8, Status);

      Assert
        (Status = Zlib.Ok,
         "byte-aligned read must succeed");

      Assert
        (Value = 1,
         "aligned read must start at the second byte");
   end Test_Align_To_Byte;

   procedure Test_Unexpected_End_Of_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Data : constant Zlib.Byte_Array := [1 => 16#00#];

      R      : Zlib.Bits.Bit_Reader;
      Status : Zlib.Status_Code;
      Value  : Natural;
   begin
      Zlib.Bits.Init (R, Data);

      Value := Zlib.Bits.Read_Bits (R, 8, Status);

      Assert
        (Status = Zlib.Ok,
         "reading first byte must succeed");

      Assert
        (Value = 0,
         "first byte must decode as zero");

      Value := Zlib.Bits.Read_Bits (R, 1, Status);

      Assert
        (Status = Zlib.Unexpected_End_Of_Input,
         "reading past the input must report Unexpected_End_Of_Input");

      Assert
        (Value = 0,
         "failed read must return zero");
   end Test_Unexpected_End_Of_Input;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Read_Single_Bits_Lsb_First'Access,
         "Read single bits LSB-first");

      Registration.Register_Routine
        (T, Test_Read_Bits_Crosses_Byte_Boundary'Access,
         "Read bits across byte boundary");

      Registration.Register_Routine
        (T, Test_Align_To_Byte'Access,
         "Align to byte boundary");

      Registration.Register_Routine
        (T, Test_Unexpected_End_Of_Input'Access,
         "Unexpected end of input");
   end Register_Tests;

end Zlib_Bits_Tests;
