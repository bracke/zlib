with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Inflate_With_Header_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib Inflate_With_Header");
   end Name;

   procedure Assert_Bytes_Equal
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
   end Assert_Bytes_Equal;

   procedure Assert_Inflates
     (Input    : Zlib.Byte_Array;
      Header   : Zlib.Header_Type;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": expected Ok");
      Assert_Bytes_Equal (Output, Expected, Message);
   end Assert_Inflates;

   procedure Assert_Fails
     (Input           : Zlib.Byte_Array;
      Header          : Zlib.Header_Type;
      Expected_Status : Zlib.Status_Code;
      Message         : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Expected_Status,
         Message & ": expected " & Zlib.Status_Image (Expected_Status)
         & ", got " & Zlib.Status_Image (Status));
   end Assert_Fails;

   procedure Assert_Fails_Not_Ok
     (Input   : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Message : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Message & ": expected failure status");
   end Assert_Fails_Not_Ok;

   Hello : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#];

   Zlib_Stored_Hello : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#05#, 5 => 16#00#,
      6 => 16#FA#, 7 => 16#FF#, 8 => 16#68#, 9 => 16#65#, 10 => 16#6C#,
      11 => 16#6C#, 12 => 16#6F#, 13 => 16#06#, 14 => 16#2C#,
      15 => 16#02#, 16 => 16#15#];

   Raw_Stored_Hello : constant Zlib.Byte_Array :=
     [1 => 16#01#, 2 => 16#05#, 3 => 16#00#, 4 => 16#FA#, 5 => 16#FF#,
      6 => 16#68#, 7 => 16#65#, 8 => 16#6C#, 9 => 16#6C#, 10 => 16#6F#];

   GZip_Hello : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Bad_GZip_CRC : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#87#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Bad_GZip_ISIZE : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#06#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Fixed_Text : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#,
      6 => 16#20#, 7 => 16#68#, 8 => 16#65#, 9 => 16#6C#, 10 => 16#6C#,
      11 => 16#6F#, 12 => 16#20#, 13 => 16#68#, 14 => 16#65#, 15 => 16#6C#,
      16 => 16#6C#, 17 => 16#6F#];

   Raw_Fixed_Text : constant Zlib.Byte_Array :=
     [1 => 16#CB#, 2 => 16#48#, 3 => 16#CD#, 4 => 16#C9#, 5 => 16#C9#,
      6 => 16#57#, 7 => 16#C8#, 8 => 16#40#, 9 => 16#90#, 10 => 16#00#];

   Dynamic_Text : constant Zlib.Byte_Array :=
     [1 => 16#4C#, 2 => 16#6F#, 3 => 16#72#, 4 => 16#65#, 5 => 16#6D#,
      6 => 16#20#, 7 => 16#69#, 8 => 16#70#, 9 => 16#73#, 10 => 16#75#,
      11 => 16#6D#, 12 => 16#20#, 13 => 16#64#, 14 => 16#6F#, 15 => 16#6C#,
      16 => 16#6F#, 17 => 16#72#, 18 => 16#20#, 19 => 16#73#, 20 => 16#69#,
      21 => 16#74#, 22 => 16#20#, 23 => 16#61#, 24 => 16#6D#, 25 => 16#65#,
      26 => 16#74#, 27 => 16#2C#, 28 => 16#20#, 29 => 16#63#, 30 => 16#6F#,
      31 => 16#6E#, 32 => 16#73#, 33 => 16#65#, 34 => 16#63#, 35 => 16#74#,
      36 => 16#65#, 37 => 16#74#, 38 => 16#75#, 39 => 16#72#, 40 => 16#20#,
      41 => 16#61#, 42 => 16#64#, 43 => 16#69#, 44 => 16#70#, 45 => 16#69#,
      46 => 16#73#, 47 => 16#63#, 48 => 16#69#, 49 => 16#6E#, 50 => 16#67#,
      51 => 16#20#, 52 => 16#65#, 53 => 16#6C#, 54 => 16#69#, 55 => 16#74#,
      56 => 16#2E#, 57 => 16#20#,
      58 => 16#4C#, 59 => 16#6F#, 60 => 16#72#, 61 => 16#65#, 62 => 16#6D#,
      63 => 16#20#, 64 => 16#69#, 65 => 16#70#, 66 => 16#73#, 67 => 16#75#,
      68 => 16#6D#, 69 => 16#20#, 70 => 16#64#, 71 => 16#6F#, 72 => 16#6C#,
      73 => 16#6F#, 74 => 16#72#, 75 => 16#20#, 76 => 16#73#, 77 => 16#69#,
      78 => 16#74#, 79 => 16#20#, 80 => 16#61#, 81 => 16#6D#, 82 => 16#65#,
      83 => 16#74#, 84 => 16#2C#, 85 => 16#20#, 86 => 16#63#, 87 => 16#6F#,
      88 => 16#6E#, 89 => 16#73#, 90 => 16#65#, 91 => 16#63#, 92 => 16#74#,
      93 => 16#65#, 94 => 16#74#, 95 => 16#75#, 96 => 16#72#, 97 => 16#20#,
      98 => 16#61#, 99 => 16#64#, 100 => 16#69#, 101 => 16#70#, 102 => 16#69#,
      103 => 16#73#, 104 => 16#63#, 105 => 16#69#, 106 => 16#6E#, 107 => 16#67#,
      108 => 16#20#, 109 => 16#65#, 110 => 16#6C#, 111 => 16#69#, 112 => 16#74#,
      113 => 16#2E#, 114 => 16#20#];

   Raw_Dynamic_Text : constant Zlib.Byte_Array :=
     [1 => 16#9D#, 2 => 16#CB#, 3 => 16#D1#, 4 => 16#09#, 5 => 16#C0#,
      6 => 16#20#, 7 => 16#0C#, 8 => 16#05#, 9 => 16#C0#, 10 => 16#55#,
      11 => 16#DE#, 12 => 16#00#, 13 => 16#A5#, 14 => 16#93#, 15 => 16#B8#,
      16 => 16#84#, 17 => 16#C4#, 18 => 16#20#, 19 => 16#0F#, 20 => 16#8C#,
      21 => 16#91#, 22 => 16#24#, 23 => 16#EE#, 24 => 16#DF#, 25 => 16#1D#,
      26 => 16#7A#, 27 => 16#FF#, 28 => 16#D7#, 29 => 16#3C#, 30 => 16#D4#,
      31 => 16#C0#, 32 => 16#93#, 33 => 16#D7#, 34 => 16#30#, 35 => 16#7C#,
      36 => 16#79#, 37 => 16#20#, 38 => 16#59#, 39 => 16#E8#, 40 => 16#A6#,
      41 => 16#F5#, 42 => 16#40#, 43 => 16#7C#, 44 => 16#A7#, 45 => 16#4A#,
      46 => 16#69#, 47 => 16#DD#, 48 => 16#40#, 49 => 16#1F#, 50 => 16#3C#,
      51 => 16#4C#, 52 => 16#E1#, 53 => 16#9E#, 54 => 16#D0#, 55 => 16#C5#,
      56 => 16#7A#, 57 => 16#D1#, 58 => 16#FE#, 59 => 16#C6#, 60 => 16#0F#];

   Truncated_Raw_Deflate : constant Zlib.Byte_Array :=
     [1 => 16#01#, 2 => 16#05#, 3 => 16#00#];

   procedure Test_Default_Equals_Zlib_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status_Default : Zlib.Status_Code;
      Status_Zlib    : Zlib.Status_Code;
      Default_Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Zlib_Stored_Hello, Zlib.Default, Status_Default);
      Zlib_Output    : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Zlib_Stored_Hello, Zlib.Zlib_Header, Status_Zlib);
   begin
      Assert (Status_Default = Zlib.Ok, "Default must decode zlib fixture");
      Assert (Status_Zlib = Zlib.Ok, "Zlib_Header must decode zlib fixture");
      Assert_Bytes_Equal (Default_Output, Zlib_Output, "Default equals Zlib_Header");
   end Test_Default_Equals_Zlib_Header;

   procedure Test_Zlib_Header_Inflates_Zlib
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates (Zlib_Stored_Hello, Zlib.Zlib_Header, Hello, "Zlib_Header fixture");
   end Test_Zlib_Header_Inflates_Zlib;

   procedure Test_GZip_Inflates_GZip
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates (GZip_Hello, Zlib.GZip, Hello, "GZip fixture");
   end Test_GZip_Inflates_GZip;

   procedure Test_Raw_Stored_Inflates
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates (Raw_Stored_Hello, Zlib.Raw_Deflate, Hello, "raw stored fixture");
   end Test_Raw_Stored_Inflates;

   procedure Test_Raw_Fixed_Inflates
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates (Raw_Fixed_Text, Zlib.Raw_Deflate, Fixed_Text, "raw fixed fixture");
   end Test_Raw_Fixed_Inflates;

   procedure Test_Raw_Dynamic_Inflates
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Inflates (Raw_Dynamic_Text, Zlib.Raw_Deflate, Dynamic_Text, "raw dynamic fixture");
   end Test_Raw_Dynamic_Inflates;

   procedure Test_Inflate_Remains_Zlib_Only
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Zlib_Stored_Hello, Status);
   begin
      Assert (Status = Zlib.Ok, "Inflate must keep zlib wrapper behavior");
      Assert_Bytes_Equal (Output, Hello, "Inflate zlib-only output");
   end Test_Inflate_Remains_Zlib_Only;

   procedure Test_Inflate_Rejects_Raw
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Raw_Stored_Hello, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, "Inflate must reject raw Deflate input");
   end Test_Inflate_Rejects_Raw;

   procedure Test_Zlib_Header_Rejects_Raw
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Fails_Not_Ok
        (Raw_Stored_Hello, Zlib.Zlib_Header,
         "Zlib_Header must reject raw Deflate input");
   end Test_Zlib_Header_Rejects_Raw;

   procedure Test_Raw_Rejects_Zlib
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Fails_Not_Ok
        (Zlib_Stored_Hello, Zlib.Raw_Deflate,
         "Raw_Deflate must reject zlib-wrapped input");
   end Test_Raw_Rejects_Zlib;

   procedure Test_GZip_Rejects_Zlib
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Fails
        (Zlib_Stored_Hello, Zlib.GZip, Zlib.Invalid_Header,
         "GZip must reject zlib-wrapped input");
   end Test_GZip_Rejects_Zlib;

   procedure Test_Bad_GZip_CRC_Invalid_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Fails
        (Bad_GZip_CRC, Zlib.GZip, Zlib.Invalid_Checksum,
         "bad gzip CRC must map to Invalid_Checksum");
   end Test_Bad_GZip_CRC_Invalid_Checksum;

   procedure Test_Bad_GZip_ISIZE_Invalid_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Fails
        (Bad_GZip_ISIZE, Zlib.GZip, Zlib.Invalid_Checksum,
         "bad gzip ISIZE must map to Invalid_Checksum");
   end Test_Bad_GZip_ISIZE_Invalid_Checksum;

   procedure Test_Truncated_Raw_Unexpected_End
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Fails
        (Truncated_Raw_Deflate, Zlib.Raw_Deflate, Zlib.Unexpected_End_Of_Input,
         "truncated raw Deflate must map to Unexpected_End_Of_Input");
   end Test_Truncated_Raw_Unexpected_End;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Default_Equals_Zlib_Header'Access,
         "Inflate_With_Header Default equals Zlib_Header");
      Registration.Register_Routine
        (T, Test_Zlib_Header_Inflates_Zlib'Access,
         "Inflate_With_Header Zlib_Header inflates zlib fixture");
      Registration.Register_Routine
        (T, Test_GZip_Inflates_GZip'Access,
         "Inflate_With_Header GZip inflates gzip fixture");
      Registration.Register_Routine
        (T, Test_Raw_Stored_Inflates'Access,
         "Inflate_With_Header Raw_Deflate inflates raw stored fixture");
      Registration.Register_Routine
        (T, Test_Raw_Fixed_Inflates'Access,
         "Inflate_With_Header Raw_Deflate inflates raw fixed fixture");
      Registration.Register_Routine
        (T, Test_Raw_Dynamic_Inflates'Access,
         "Inflate_With_Header Raw_Deflate inflates raw dynamic fixture");
      Registration.Register_Routine
        (T, Test_Inflate_Remains_Zlib_Only'Access,
         "Inflate remains zlib-wrapper-only");
      Registration.Register_Routine
        (T, Test_Inflate_Rejects_Raw'Access,
         "Inflate rejects raw Deflate input");
      Registration.Register_Routine
        (T, Test_Zlib_Header_Rejects_Raw'Access,
         "Inflate_With_Header Zlib_Header rejects raw Deflate input");
      Registration.Register_Routine
        (T, Test_Raw_Rejects_Zlib'Access,
         "Inflate_With_Header Raw_Deflate rejects zlib-wrapped input");
      Registration.Register_Routine
        (T, Test_GZip_Rejects_Zlib'Access,
         "Inflate_With_Header GZip rejects zlib-wrapped input");
      Registration.Register_Routine
        (T, Test_Bad_GZip_CRC_Invalid_Checksum'Access,
         "bad gzip CRC maps to Invalid_Checksum");
      Registration.Register_Routine
        (T, Test_Bad_GZip_ISIZE_Invalid_Checksum'Access,
         "bad gzip ISIZE maps to Invalid_Checksum");
      Registration.Register_Routine
        (T, Test_Truncated_Raw_Unexpected_End'Access,
         "truncated raw Deflate maps to Unexpected_End_Of_Input");
   end Register_Tests;

end Zlib_Inflate_With_Header_Tests;
