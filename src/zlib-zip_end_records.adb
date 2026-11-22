package body Zlib.ZIP_End_Records is

   package SIO renames Ada.Streams.Stream_IO;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   --  The end record's fixed part, the ZIP64 locator's and record's, and the
   --  most of the tail they can sit in (a comment is at most 65_535 bytes;
   --  the locator and the ZIP64 record come before the end record).
   Record_Length  : constant := 22;
   Locator_Length : constant := 20;
   Zip64_Length   : constant := 56;
   Tail_Window    : constant := Record_Length + 65_535 + Locator_Length + Zip64_Length;

   EOCD_Signature     : constant Interfaces.Unsigned_32 := 16#0605_4B50#;
   Locator_Signature  : constant Interfaces.Unsigned_32 := 16#0706_4B50#;
   Z64_EOCD_Signature : constant Interfaces.Unsigned_32 := 16#0606_4B50#;

   function U16_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_16
   is
   begin
      return Interfaces.Unsigned_16 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (Pos + 1)), 8);
   end U16_At;

   function U32_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      for Offset in reverse 0 .. 3 loop
         Result := Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_32 (Data (Pos + Offset));
      end loop;
      return Result;
   end U32_At;

   function U64_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. 7 loop
         Result := Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (Pos + Offset));
      end loop;
      return Result;
   end U64_At;

   --  Stream_IO indices are 1-based; ZIP offsets are 0-based.
   procedure Read_At
     (File   : in out SIO.File_Type;
      Offset : Interfaces.Unsigned_64;
      Into   : out Byte_Array;
      Ok     : out Boolean)
   is
      Buffer : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Into'Length));
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Into := [others => 0];
      Ok := False;

      if Into'Length = 0 then
         Ok := True;
         return;
      end if;

      SIO.Set_Index (File, SIO.Positive_Count (Offset + 1));
      SIO.Read (File, Buffer, Last);
      if Last /= Buffer'Last then
         return;
      end if;

      declare
         Target : Natural := Into'First;
      begin
         for I in Buffer'Range loop
            Into (Target) := Byte (Buffer (I));
            Target := Target + 1;
         end loop;
      end;
      Ok := True;
   end Read_At;

   procedure Locate
     (File      : in out SIO.File_Type;
      File_Size : Interfaces.Unsigned_64;
      Result    : out End_Record)
   is
      Window_Length : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64'Min (File_Size, Tail_Window);
      --  File position of the window's first byte.
      Start  : constant Interfaces.Unsigned_64 := File_Size - Window_Length;
      Window : Byte_Array (0 .. Natural (Window_Length) - 1);
      Ok     : Boolean;

      --  The ZIP64 record the locator before the end record at Window (At)
      --  points to: in the window where stated, else right before the
      --  locator (where every writer puts it; a stub in front shifts the
      --  stated offset), else read where stated. Result.Found stays False
      --  when there is no valid locator or record.
      procedure Read_Zip64 (At_Index : Natural) is
         Header  : Byte_Array (0 .. Zip64_Length - 1);
         Shifted : Boolean := False;
         Locator : Natural;
         Stated  : Interfaces.Unsigned_64;
      begin
         if At_Index < Locator_Length then
            return;
         end if;
         Locator := At_Index - Locator_Length;
         if U32_At (Window, Locator) /= Locator_Signature then
            return;
         end if;
         Stated := U64_At (Window, Locator + 8);
         if Stated >= Start
           and then Stated - Start + Zip64_Length <= Interfaces.Unsigned_64 (Locator)
           and then U32_At (Window, Natural (Stated - Start)) = Z64_EOCD_Signature
         then
            Header := Window (Natural (Stated - Start) .. Natural (Stated - Start) + Zip64_Length - 1);
         elsif Locator >= Zip64_Length
           and then U32_At (Window, Locator - Zip64_Length) = Z64_EOCD_Signature
         then
            Header := Window (Locator - Zip64_Length .. Locator - 1);
            Shifted := True;
         elsif Stated <= File_Size and then File_Size - Stated >= Zip64_Length then
            Read_At (File, Stated, Header, Ok);
            if not Ok or else U32_At (Header, 0) /= Z64_EOCD_Signature then
               return;
            end if;
         else
            return;
         end if;
         declare
            --  Total number of entries (bytes 32 .. 39).
            Count : constant Interfaces.Unsigned_64 := U64_At (Header, 32);
            Over  : constant Boolean := Count > Interfaces.Unsigned_64 (Natural'Last);
         begin
            Result :=
              (Found     => True,
               Count     => (if Over then Natural'Last else Natural (Count)),
               Capped    => Over,
               CD_Size   => U64_At (Header, 40),
               CD_Offset => U64_At (Header, 48),
               Shifted   => Shifted);
         end;
      end Read_Zip64;
   begin
      Result := (others => <>);
      if File_Size < Record_Length then
         return;
      end if;
      Read_At (File, Start, Window, Ok);
      if not Ok then
         return;
      end if;

      for P in reverse Window'First .. Window'Last - (Record_Length - 1) loop
         if U32_At (Window, P) = EOCD_Signature
           and then P + Record_Length + Natural (U16_At (Window, P + 20)) <= Window'Length
         then
            declare
               Count16  : constant Interfaces.Unsigned_16 := U16_At (Window, P + 10);
               Size32   : constant Interfaces.Unsigned_32 := U32_At (Window, P + 12);
               Off32    : constant Interfaces.Unsigned_32 := U32_At (Window, P + 16);
               Position : constant Interfaces.Unsigned_64 := Start + Interfaces.Unsigned_64 (P);
            begin
               if Count16 = 16#FFFF# or else Size32 = 16#FFFF_FFFF# or else Off32 = 16#FFFF_FFFF#
                 or else (P >= Locator_Length
                          and then U32_At (Window, P - Locator_Length) = Locator_Signature)
               then
                  Read_Zip64 (P);
                  if Result.Found then
                     return;
                  end if;
               end if;
               if Count16 = 16#FFFF# then
                  return;
               elsif Interfaces.Unsigned_64 (Off32) + Interfaces.Unsigned_64 (Size32) <= Position then
                  Result :=
                    (Found     => True,
                     Count     => Natural (Count16),
                     Capped    => False,
                     CD_Offset => Interfaces.Unsigned_64 (Off32),
                     CD_Size   => Interfaces.Unsigned_64 (Size32),
                     Shifted   => False);
                  return;
               end if;
            end;
         end if;
      end loop;
   end Locate;

end Zlib.ZIP_End_Records;
