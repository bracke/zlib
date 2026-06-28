with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.Bit_Writer;

package body Zlib_Bit_Writer_Tests is
   use type Zlib.Byte;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Bit_Writer");
   end Name;

   procedure Assert_Same
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Same;

   procedure Test_Writes_Bits_Lsb_First
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W : Zlib.Bit_Writer.Writer;
   begin
      Zlib.Bit_Writer.Reset (W);
      Zlib.Bit_Writer.Write_Bits (W, 2#101#, 3);
      Zlib.Bit_Writer.Write_Bits (W, 2#10#, 2);
      Zlib.Bit_Writer.Flush_Byte (W);

      Assert_Same
        (Actual   => Zlib.Bit_Writer.To_Array (W),
         Expected => [1 => 2#0001_0101#],
         Message  => "LSB-first bit output");
   end Test_Writes_Bits_Lsb_First;

   procedure Test_Flushes_Partial_Final_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W : Zlib.Bit_Writer.Writer;
   begin
      Zlib.Bit_Writer.Reset (W);
      Zlib.Bit_Writer.Write_Bits (W, 1, 1);

      Assert
        (not Zlib.Bit_Writer.Is_Byte_Aligned (W),
         "writer must be unaligned before flushing one bit");

      Zlib.Bit_Writer.Flush_Byte (W);

      Assert
        (Zlib.Bit_Writer.Is_Byte_Aligned (W),
         "writer must be byte-aligned after Flush_Byte");

      Assert_Same
        (Actual   => Zlib.Bit_Writer.To_Array (W),
         Expected => [1 => 1],
         Message  => "partial byte flush");
   end Test_Flushes_Partial_Final_Byte;

   procedure Test_Byte_Aligned_Append
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W : Zlib.Bit_Writer.Writer;
   begin
      Zlib.Bit_Writer.Reset (W);
      Zlib.Bit_Writer.Write_Byte_Aligned (W, 16#78#);
      Zlib.Bit_Writer.Write_Bits (W, 2#011#, 3);
      Zlib.Bit_Writer.Flush_Byte (W);
      Zlib.Bit_Writer.Write_Byte_Aligned (W, 16#01#);

      Assert_Same
        (Actual   => Zlib.Bit_Writer.To_Array (W),
         Expected => [1 => 16#78#, 2 => 2#0000_0011#, 3 => 16#01#],
         Message  => "aligned byte append around bit payload");
   end Test_Byte_Aligned_Append;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Writes_Bits_Lsb_First'Access,
         "Write bits LSB-first");

      Registration.Register_Routine
        (T, Test_Flushes_Partial_Final_Byte'Access,
         "Flush partial final byte");

      Registration.Register_Routine
        (T, Test_Byte_Aligned_Append'Access,
         "Append byte-aligned bytes");
   end Register_Tests;

end Zlib_Bit_Writer_Tests;
