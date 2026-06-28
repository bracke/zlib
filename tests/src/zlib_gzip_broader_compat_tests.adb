with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_GZip_Broader_Compat_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;

   Expected_Hello : constant Zlib.Byte_Array :=
     [1 => Character'Pos ('h'),
      2 => Character'Pos ('e'),
      3 => Character'Pos ('l'),
      4 => Character'Pos ('l'),
      5 => Character'Pos ('o')];

   GZip_FExtra : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#04#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#04#, 12 => 16#00#,
      13 => 16#61#, 14 => 16#62#, 15 => 16#63#, 16 => 16#64#,
      17 => 16#CB#, 18 => 16#48#, 19 => 16#CD#, 20 => 16#C9#,
      21 => 16#C9#, 22 => 16#07#, 23 => 16#00#, 24 => 16#86#,
      25 => 16#A6#, 26 => 16#10#, 27 => 16#36#, 28 => 16#05#,
      29 => 16#00#, 30 => 16#00#, 31 => 16#00#];

   GZip_All_Optional : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#1E#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#02#, 12 => 16#00#,
      13 => 16#AB#, 14 => 16#CD#, 15 => 16#61#, 16 => 16#00#,
      17 => 16#62#, 18 => 16#00#, 19 => 16#88#, 20 => 16#AF#,
      21 => 16#CB#, 22 => 16#48#, 23 => 16#CD#, 24 => 16#C9#,
      25 => 16#C9#, 26 => 16#07#, 27 => 16#00#, 28 => 16#86#,
      29 => 16#A6#, 30 => 16#10#, 31 => 16#36#, 32 => 16#05#,
      33 => 16#00#, 34 => 16#00#, 35 => 16#00#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib gzip broader compatibility");
   end Name;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

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

   procedure Assert_Inflates_To
     (Input    : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
      Status : Zlib.Status_Code;
      Output : Zlib.Byte_Array (1 .. Expected'Length);
   begin
      Output := Zlib.Inflate_With_Header (Input, Zlib.GZip, Status);
      Assert (Status = Zlib.Ok, Message & ": inflate status");
      Assert_Same (Output, Expected, Message);
   end Assert_Inflates_To;

   procedure Assert_Stream_Inflates_Byte_By_Byte
     (Input    : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
      Filter : Zlib.Filter_Type;
      Result : Zlib.Byte_Array (1 .. Expected'Length);
      Last   : Natural := Result'First - 1;
      Pos    : Natural := Input'First;
   begin
      Zlib.Inflate_Init (Filter, Header => Zlib.GZip);

      while Pos <= Input'Last loop
         declare
            In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
              [1 => Ada.Streams.Stream_Element (Input (Pos))];
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 2);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
            if Out_Last /= Before_First (Out_Data) then
               for I in Out_Data'First .. Out_Last loop
                  Last := Last + 1;
                  Result (Last) := Zlib.Byte (Out_Data (I));
               end loop;
            end if;
            if In_Last /= Before_First (In_Data) then
               Pos := Pos + 1;
            end if;
         end;
      end loop;

      for Guard in 1 .. 128 loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 2);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            if Out_Last /= Before_First (Out_Data) then
               for I in Out_Data'First .. Out_Last loop
                  Last := Last + 1;
                  Result (Last) := Zlib.Byte (Out_Data (I));
               end loop;
            end if;
            exit when Zlib.Stream_End (Filter);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), Message & ": stream end");
      Zlib.Close (Filter);
      Assert (Last = Expected'Last, Message & ": decoded length");
      Assert_Same (Result, Expected, Message);
   end Assert_Stream_Inflates_Byte_By_Byte;

   procedure Test_Inflate_FExtra (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates_To (GZip_FExtra, Expected_Hello, "gzip FEXTRA inflate");
   end Test_Inflate_FExtra;

   procedure Test_Inflate_FExtra_Split_Byte_By_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Stream_Inflates_Byte_By_Byte
        (GZip_FExtra, Expected_Hello, "gzip FEXTRA byte-by-byte inflate");
   end Test_Inflate_FExtra_Split_Byte_By_Byte;

   procedure Test_Inflate_FExtra_Name_Comment (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates_To
        (GZip_All_Optional, Expected_Hello, "gzip FEXTRA FNAME FCOMMENT FHCRC inflate");
   end Test_Inflate_FExtra_Name_Comment;

   procedure Test_Truncated_XLEN_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Input  : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#04#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#FF#, 11 => 16#04#];
      Output : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Input, Zlib.GZip, Status);
   begin
      Assert (Status /= Zlib.Ok, "truncated XLEN must not inflate");
      Assert (Output'Length = 0, "truncated XLEN produces no one-shot output");
   end Test_Truncated_XLEN_Rejected;

   procedure Test_Truncated_FExtra_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Input  : constant Zlib.Byte_Array := GZip_FExtra (1 .. 14);
      Output : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Input, Zlib.GZip, Status);
   begin
      Assert (Status /= Zlib.Ok, "truncated FEXTRA must not inflate");
      Assert (Output'Length = 0, "truncated FEXTRA produces no one-shot output");
   end Test_Truncated_FExtra_Rejected;

   procedure Test_Output_FExtra_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Extra    : constant Zlib.Byte_Array := [1 => 16#41#, 2 => 0, 3 => 16#FF#, 4 => 16#42#];
   begin
      Zlib.Set_Extra (Metadata, Extra);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip FEXTRA output must succeed");
         Assert (GZ (4) = 16#04#, "gzip FEXTRA output sets FEXTRA only");
         Assert (GZ (11) = 4 and then GZ (12) = 0, "gzip FEXTRA output emits little-endian XLEN");
         Assert (GZ (13) = Extra (1) and then GZ (14) = Extra (2)
           and then GZ (15) = Extra (3) and then GZ (16) = Extra (4),
           "gzip FEXTRA output emits exact extra bytes");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip FEXTRA output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "gzip FEXTRA output roundtrip");
      end;
   end Test_Output_FExtra_Roundtrip;

   procedure Test_Output_FExtra_FHCRC_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Extra (Metadata, [1 => 16#AB#, 2 => 16#CD#]);
      Zlib.Set_Name (Metadata, "extra.bin");
      Zlib.Set_Comment (Metadata, "with header crc");
      Zlib.Set_Header_CRC (Metadata, True);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Fixed, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip FEXTRA+FHCRC output must succeed");
         Assert ((GZ (4) and 16#1E#) = 16#1E#, "gzip FEXTRA+FHCRC output sets optional flags");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip FEXTRA+FHCRC output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "gzip FEXTRA+FHCRC output roundtrip");
      end;
   end Test_Output_FExtra_FHCRC_Roundtrip;

   procedure Test_Default_GZip_Output_Unchanged (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      GZ     : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Status);
   begin
      Assert (Status = Zlib.Ok, "default gzip output must succeed");
      Assert (GZ (1) = 16#1F# and then GZ (2) = 16#8B# and then GZ (3) = 16#08#,
        "default gzip output magic/method unchanged");
      Assert (GZ (4) = 0, "default gzip output has no optional flags");
      Assert (GZ (5) = 0 and then GZ (6) = 0 and then GZ (7) = 0 and then GZ (8) = 0,
        "default gzip output MTIME unchanged");
      Assert (GZ (9) = 0, "default gzip output XFL unchanged");
      Assert (GZ (10) = 255, "default gzip output OS unchanged");
   end Test_Default_GZip_Output_Unchanged;

   procedure Test_Output_XFL_OS_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_XFL (Metadata, 16#04#);
      Zlib.Set_OS (Metadata, 16#03#);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip XFL/OS output must succeed");
         Assert (GZ (4) = 0, "gzip XFL/OS output does not set optional flags");
         Assert (GZ (9) = 16#04#, "gzip output emits explicit XFL");
         Assert (GZ (10) = 16#03#, "gzip output emits explicit OS");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip XFL/OS output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "gzip XFL/OS output roundtrip");
      end;
   end Test_Output_XFL_OS_Roundtrip;

   procedure Test_Output_Empty_FExtra_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Extra    : constant Zlib.Byte_Array (1 .. 0) := [];
   begin
      Zlib.Set_Extra (Metadata, Extra);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "empty gzip FEXTRA output must succeed");
         Assert (GZ (4) = 16#04#, "empty gzip FEXTRA output sets FEXTRA");
         Assert (GZ (11) = 0 and then GZ (12) = 0, "empty gzip FEXTRA output emits zero XLEN");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "empty gzip FEXTRA output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "empty gzip FEXTRA output roundtrip");
      end;
   end Test_Output_Empty_FExtra_Roundtrip;

   procedure Test_Long_Metadata_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Long_Name : constant String (1 .. 300) := [others => 'n'];
      Long_Comm : constant String (1 .. 300) := [others => 'c'];
   begin
      Zlib.Set_Name (Metadata, Long_Name);
      Zlib.Set_Comment (Metadata, Long_Comm);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Dynamic, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "long gzip metadata output must succeed");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "long gzip metadata output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "long gzip metadata roundtrip");
      end;
   end Test_Long_Metadata_Roundtrip;

   procedure Test_Invalid_NUL_Name_Comment_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
   begin
      declare
         Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      begin
         Zlib.Set_Name (Metadata, "bad" & Character'Val (0) & "name");
         declare
            GZ : constant Zlib.Byte_Array :=
              Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
         begin
            Assert (Status /= Zlib.Ok, "embedded NUL in FNAME must be rejected");
            Assert (GZ'Length = 0, "embedded NUL in FNAME yields empty output");
         end;
      end;

      declare
         Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      begin
         Zlib.Set_Comment (Metadata, "bad" & Character'Val (0) & "comment");
         declare
            GZ : constant Zlib.Byte_Array :=
              Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
         begin
            Assert (Status /= Zlib.Ok, "embedded NUL in FCOMMENT must be rejected");
            Assert (GZ'Length = 0, "embedded NUL in FCOMMENT yields empty output");
         end;
      end;
   end Test_Invalid_NUL_Name_Comment_Rejected;

   procedure Test_Invalid_Extra_Length_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Too_Long : constant Zlib.Byte_Array (1 .. 65_536) := [others => 0];
   begin
      Zlib.Set_Extra (Metadata, Too_Long);
      declare
         GZ : constant Zlib.Byte_Array :=
           Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
      begin
         Assert (Status /= Zlib.Ok, "oversized FEXTRA must be rejected");
         Assert (GZ'Length = 0, "oversized FEXTRA yields empty output");
      end;
   end Test_Invalid_Extra_Length_Rejected;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Inflate_FExtra'Access, "inflate gzip with FEXTRA");
      Register_Routine
        (T, Test_Inflate_FExtra_Split_Byte_By_Byte'Access,
         "inflate gzip with FEXTRA split byte-by-byte");
      Register_Routine
        (T, Test_Inflate_FExtra_Name_Comment'Access,
         "inflate gzip with FEXTRA FNAME FCOMMENT FHCRC");
      Register_Routine (T, Test_Truncated_XLEN_Rejected'Access, "truncated XLEN rejected");
      Register_Routine (T, Test_Truncated_FExtra_Rejected'Access, "truncated FEXTRA rejected");
      Register_Routine (T, Test_Output_FExtra_Roundtrip'Access, "gzip output with FEXTRA roundtrips");
      Register_Routine
        (T, Test_Output_FExtra_FHCRC_Roundtrip'Access,
         "gzip output with FEXTRA FHCRC roundtrips");
      Register_Routine (T, Test_Default_GZip_Output_Unchanged'Access, "default gzip output unchanged");
      Register_Routine (T, Test_Output_XFL_OS_Roundtrip'Access, "gzip output with explicit XFL/OS roundtrips");
      Register_Routine (T, Test_Output_Empty_FExtra_Roundtrip'Access, "gzip output with empty FEXTRA roundtrips");
      Register_Routine (T, Test_Long_Metadata_Roundtrip'Access, "long metadata roundtrips");
      Register_Routine
        (T, Test_Invalid_NUL_Name_Comment_Rejected'Access,
         "invalid embedded NUL in name/comment rejected");
      Register_Routine (T, Test_Invalid_Extra_Length_Rejected'Access, "invalid extra length rejected");
   end Register_Tests;
end Zlib_GZip_Broader_Compat_Tests;
