with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Zlib;

procedure Quickstart is
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

   Plain : constant Zlib.Byte_Array :=
     [16#68#, 16#65#, 16#6C#, 16#6C#, 16#6F#];

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;

   procedure Require_Ok (Operation : String) is
   begin
      if Status /= Zlib.Ok then
         Fail (Operation & " failed: " & Zlib.Status_Image (Status));
      end if;
   end Require_Ok;

   procedure Write_File (Path : String; Data : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      for B of Data loop
         Ada.Streams.Stream_IO.Write
           (File, [1 => Ada.Streams.Stream_Element (B)]);
      end loop;
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Write_File;

   procedure Remove_If_Present (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Remove_If_Present;

begin
   declare
      Packed : constant Zlib.Byte_Array :=
        Zlib.Deflate (Plain, Status => Status);
   begin
      Require_Ok ("zlib deflate");

      declare
         Back : constant Zlib.Byte_Array :=
           Zlib.Inflate (Packed, Status);
      begin
         Require_Ok ("zlib inflate");
         if Back /= Plain then
            Fail ("zlib roundtrip produced different bytes");
         end if;
      end;
   end;

   declare
      Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Status => Status);
   begin
      Require_Ok ("gzip output");

      declare
         Back : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Gz, Zlib.GZip, Status);
      begin
         Require_Ok ("gzip inflate");
         if Back /= Plain then
            Fail ("gzip roundtrip produced different bytes");
         end if;
      end;
   end;

   declare
      Raw : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Plain, Status => Status);
   begin
      Require_Ok ("raw deflate output");

      declare
         Back : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Raw, Status);
      begin
         Require_Ok ("raw deflate inflate");
         if Back /= Plain then
            Fail ("raw Deflate roundtrip produced different bytes");
         end if;
      end;
   end;

   declare
      Input_Path  : constant String := "examples/obj/quickstart-input.bin";
      Zlib_Path   : constant String := "examples/obj/quickstart-input.bin.z";
      GZip_Path   : constant String := "examples/obj/quickstart-input.bin.gz";
      Raw_Path    : constant String := "examples/obj/quickstart-input.bin.deflate";
      Output_Path : constant String := "examples/obj/quickstart-input.bin.out";
   begin
      Remove_If_Present (Input_Path);
      Remove_If_Present (Zlib_Path);
      Remove_If_Present (GZip_Path);
      Remove_If_Present (Raw_Path);
      Remove_If_Present (Output_Path);

      Write_File (Input_Path, Plain);

      Zlib.Deflate_File (Input_Path, Zlib_Path, Status => Status);
      Require_Ok ("zlib file deflate");

      Zlib.Inflate_File (Zlib_Path, Output_Path, Status => Status);
      Require_Ok ("zlib file inflate");

      Zlib.GZip_File (Input_Path, GZip_Path, Status => Status);
      Require_Ok ("gzip file output");

      Zlib.Deflate_Raw_File (Input_Path, Raw_Path, Status => Status);
      Require_Ok ("raw Deflate file output");
   end;

   Ada.Text_IO.Put_Line ("quickstart ok");
end Quickstart;
