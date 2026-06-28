package body Zlib.CRC32_Internal is
   use type Interfaces.Unsigned_32;

   type CRC_Table is array (Ada.Streams.Stream_Element range 0 .. 255)
     of Interfaces.Unsigned_32;

   function Build_Table return CRC_Table is
      Polynomial : constant Interfaces.Unsigned_32 := 16#EDB8_8320#;
      C          : Interfaces.Unsigned_32;
      Result     : CRC_Table;
   begin
      for I in Result'Range loop
         C := Interfaces.Unsigned_32 (I);

         for J in 1 .. 8 loop
            pragma Unreferenced (J);

            if (C and 1) /= 0 then
               C := Interfaces.Shift_Right (C, 1) xor Polynomial;
            else
               C := Interfaces.Shift_Right (C, 1);
            end if;
         end loop;

         Result (I) := C;
      end loop;

      return Result;
   end Build_Table;

   Table : constant CRC_Table := Build_Table;

   procedure Reset
     (State : out CRC32_State)
   is
   begin
      State.CRC := 16#FFFF_FFFF#;
   end Reset;

   procedure Update_Raw
     (CRC : in out Interfaces.Unsigned_32;
      B   : Ada.Streams.Stream_Element)
   is
      Index : constant Ada.Streams.Stream_Element :=
        Ada.Streams.Stream_Element
          ((CRC xor Interfaces.Unsigned_32 (B)) and 16#FF#);
   begin
      CRC := Interfaces.Shift_Right (CRC, 8) xor Table (Index);
   end Update_Raw;

   procedure Update
     (State : in out CRC32_State;
      B     : Ada.Streams.Stream_Element)
   is
   begin
      Update_Raw (State.CRC, B);
   end Update;

   procedure Update
     (State : in out CRC32_State;
      Data  : Ada.Streams.Stream_Element_Array)
   is
   begin
      for I in Data'Range loop
         Update (State, Data (I));
      end loop;
   end Update;

   function Value
     (State : CRC32_State)
      return Interfaces.Unsigned_32
   is
   begin
      return State.CRC xor 16#FFFF_FFFF#;
   end Value;
end Zlib.CRC32_Internal;
