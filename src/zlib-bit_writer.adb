package body Zlib.Bit_Writer is

   procedure Reset
     (W : out Writer)
   is
   begin
      W.Data.Clear;
      W.Current_Byte := 0;
      W.Bit_Index := 0;
   end Reset;

   procedure Append_Current
     (W : in out Writer)
   is
   begin
      W.Data.Append (W.Current_Byte);
      W.Current_Byte := 0;
      W.Bit_Index := 0;
   end Append_Current;

   procedure Write_Bits
     (W     : in out Writer;
      Value : Natural;
      Count : Natural)
   is
      Work : Natural := Value;
   begin
      for I in 1 .. Count loop
         if Work mod 2 = 1 then
            W.Current_Byte := W.Current_Byte or Zlib.Byte (2 ** W.Bit_Index);
         end if;

         Work := Work / 2;

         if W.Bit_Index = 7 then
            Append_Current (W);
         else
            W.Bit_Index := W.Bit_Index + 1;
         end if;
      end loop;
   end Write_Bits;

   procedure Write_Byte_Aligned
     (W : in out Writer;
      B : Zlib.Byte)
   is
   begin
      pragma Assert
        (W.Bit_Index = 0,
         "Write_Byte_Aligned requires byte-aligned writer");
      W.Data.Append (B);
   end Write_Byte_Aligned;

   procedure Flush_Byte
     (W : in out Writer)
   is
   begin
      if W.Bit_Index /= 0 then
         Append_Current (W);
      end if;
   end Flush_Byte;

   function Is_Byte_Aligned
     (W : Writer)
      return Boolean
   is
   begin
      return W.Bit_Index = 0;
   end Is_Byte_Aligned;

   function To_Array
     (W : Writer)
      return Zlib.Byte_Array
   is
   begin
      if W.Data.Is_Empty then
         declare
            Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Zlib.Byte_Array (1 .. Natural (W.Data.Length));
         Out_I  : Natural := Result'First;
      begin
         for B of W.Data loop
            Result (Out_I) := B;
            Out_I := Out_I + 1;
         end loop;

         return Result;
      end;
   end To_Array;

end Zlib.Bit_Writer;
