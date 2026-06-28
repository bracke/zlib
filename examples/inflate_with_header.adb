with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;

procedure Inflate_With_Header is
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

   Zlib_Hello : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#05#, 5 => 16#00#,
      6 => 16#FA#, 7 => 16#FF#, 8 => 16#68#, 9 => 16#65#, 10 => 16#6C#,
      11 => 16#6C#, 12 => 16#6F#, 13 => 16#06#, 14 => 16#2C#,
      15 => 16#02#, 16 => 16#15#];

   GZip_Hello : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Raw_Hello : constant Zlib.Byte_Array :=
     [1 => 16#01#, 2 => 16#05#, 3 => 16#00#, 4 => 16#FA#, 5 => 16#FF#,
      6 => 16#68#, 7 => 16#65#, 8 => 16#6C#, 9 => 16#6C#, 10 => 16#6F#];

   procedure Show
     (Label  : String;
      Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type)
   is
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
      pragma Unreferenced (Output);
   begin
      Ada.Text_IO.Put_Line (Label & ": " & Zlib.Status_Image (Status));
      if Status /= Zlib.Ok then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Show;
begin
   Show ("zlib", Zlib_Hello, Zlib.Zlib_Header);
   Show ("gzip", GZip_Hello, Zlib.GZip);
   Show ("raw", Raw_Hello, Zlib.Raw_Deflate);
end Inflate_With_Header;
