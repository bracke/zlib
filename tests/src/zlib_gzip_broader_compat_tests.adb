with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces; use type Interfaces.Unsigned_32;
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

   procedure Test_Read_GZip_Header_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Write_Md : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Write_Md, "hello.txt");
      Zlib.Set_Comment (Write_Md, "a comment");
      Zlib.Set_MTime (Write_Md, 16#12345678#);
      declare
         GZ      : constant Zlib.Byte_Array :=
           Zlib.GZip (F.Plain_Stored, Zlib.Stored, Write_Md, Status);
         Read_Md : Zlib.GZip_Metadata;
         RStatus : Zlib.Status_Code;
      begin
         Assert (Status = Zlib.Ok, "gzip with name/comment/mtime must write");
         Zlib.Read_GZip_Header (GZ, Read_Md, RStatus);
         Assert (RStatus = Zlib.Ok, "reading a valid gzip header must succeed");
         Assert (Zlib.Has_Name (Read_Md) and then Zlib.Name (Read_Md) = "hello.txt",
                 "gzip header FNAME roundtrips");
         Assert (Zlib.Has_Comment (Read_Md)
                 and then Zlib.Comment (Read_Md) = "a comment",
                 "gzip header FCOMMENT roundtrips");
         Assert (Zlib.MTime (Read_Md) = 16#12345678#,
                 "gzip header MTIME roundtrips");
         --  10-byte fixed header + "hello.txt"+NUL (10) + "a comment"+NUL (10).
         Assert (Zlib.Header_Length (Read_Md) = 30,
                 "gzip header length is the offset of the first Deflate byte");
         Assert (not Zlib.Has_Header_CRC (Read_Md),
                 "this header carries no FHCRC field");
      end;
   end Test_Read_GZip_Header_Roundtrip;

   procedure Test_Read_GZip_Header_HCRC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Read_Md : Zlib.GZip_Metadata;
      RStatus : Zlib.Status_Code;
      Bad     : Zlib.Byte_Array := GZip_All_Optional;
   begin
      --  The all-optional fixture carries a valid FHCRC field.
      Zlib.Read_GZip_Header (GZip_All_Optional, Read_Md, RStatus);
      Assert (RStatus = Zlib.Ok, "a valid FHCRC header must read");
      Assert (Zlib.Has_Header_CRC (Read_Md), "FHCRC presence is reported");
      --  fixed 10 + FEXTRA (2+2) + FNAME (2) + FCOMMENT (2) + FHCRC (2) = 20.
      Assert (Zlib.Header_Length (Read_Md) = 20,
              "header length spans every optional field");

      --  Corrupt the first FHCRC byte (array index 19) so the checksum fails.
      Bad (19) := Bad (19) xor 16#FF#;
      Zlib.Read_GZip_Header (Bad, Read_Md, RStatus);
      Assert (RStatus = Zlib.Invalid_Checksum,
              "a wrong FHCRC is rejected as Invalid_Checksum");
   end Test_Read_GZip_Header_HCRC;

   procedure Test_Read_GZip_Header_Truncated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Write_Md : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Write_Md, "truncated.bin");
      declare
         GZ      : constant Zlib.Byte_Array :=
           Zlib.GZip (F.Plain_Stored, Zlib.Stored, Write_Md, Status);
         Read_Md : Zlib.GZip_Metadata;
         RStatus : Zlib.Status_Code;
      begin
         Assert (Status = Zlib.Ok, "setup gzip must write");
         --  Cut two bytes into the FNAME field (fixed header is 10 bytes) so no
         --  NUL terminator is present within the slice.
         Zlib.Read_GZip_Header (GZ (GZ'First .. GZ'First + 11), Read_Md, RStatus);
         Assert (RStatus = Zlib.Unexpected_End_Of_Input,
                 "a header truncated inside FNAME is rejected as truncated");
      end;
   end Test_Read_GZip_Header_Truncated;

   procedure Test_Read_GZip_Header_Reserved (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Read_Md : Zlib.GZip_Metadata;
      RStatus : Zlib.Status_Code;
      --  A minimal gzip header with a reserved FLG bit (0x20) set.
      Reserved : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#20#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#FF#, 11 => 16#00#, 12 => 16#00#];
   begin
      Zlib.Read_GZip_Header (Reserved, Read_Md, RStatus);
      Assert (RStatus = Zlib.Invalid_Header,
              "a header with a reserved FLG bit is rejected");
   end Test_Read_GZip_Header_Reserved;

   procedure Test_Read_GZip_Header_Not_GZip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Not_GZ  : constant Zlib.Byte_Array :=
        [1 => 16#50#, 2 => 16#4B#, 3 => 16#03#, 4 => 16#04#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#00#, 11 => 16#00#, 12 => 16#00#];
      Read_Md : Zlib.GZip_Metadata;
      RStatus : Zlib.Status_Code;
   begin
      Zlib.Read_GZip_Header (Not_GZ, Read_Md, RStatus);
      Assert (RStatus = Zlib.Invalid_Header,
              "a non-gzip buffer is rejected as an invalid header");
   end Test_Read_GZip_Header_Not_GZip;

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
      Register_Routine
        (T, Test_Read_GZip_Header_Roundtrip'Access, "gzip header read roundtrips name/comment/mtime");
      Register_Routine
        (T, Test_Read_GZip_Header_HCRC'Access, "gzip header read validates FHCRC and reports length");
      Register_Routine
        (T, Test_Read_GZip_Header_Truncated'Access, "gzip header read rejects a truncated header");
      Register_Routine
        (T, Test_Read_GZip_Header_Reserved'Access, "gzip header read rejects a reserved FLG bit");
      Register_Routine
        (T, Test_Read_GZip_Header_Not_GZip'Access, "gzip header read rejects a non-gzip buffer");
   end Register_Tests;
end Zlib_GZip_Broader_Compat_Tests;
