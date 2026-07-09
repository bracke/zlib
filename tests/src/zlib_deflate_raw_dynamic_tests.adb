with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Raw_Dynamic_Tests is
   use type Zlib.Byte;

   package SIO renames Ada.Streams.Stream_IO;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib one-shot raw dynamic Deflate compression");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

   function Hello return Zlib.Byte_Array is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   end Hello;
   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Write_File
     (Path : String;
      Data : Zlib.Byte_Array)
   is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Data'Length > 0 then
         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
         begin
            for I in Data'Range loop
               Buffer (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;
            SIO.Write (File, Buffer);
         end;
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_File;

   function Read_File (Path : String) return Zlib.Byte_Array is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            return Empty;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
            Result : Zlib.Byte_Array (1 .. Size);
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_File;

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

   procedure Assert_Roundtrip
     (Input   : Zlib.Byte_Array;
      Message : String)
   is
      Status     : Zlib.Status_Code := Zlib.Ok;
      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Zlib.Dynamic, Status);
      Inflated_Status : Zlib.Status_Code := Zlib.Ok;
      Inflated : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Inflated_Status);
      Default_Status : Zlib.Status_Code := Zlib.Ok;
      Zlib_Status    : Zlib.Status_Code := Zlib.Ok;
      GZip_Status    : Zlib.Status_Code := Zlib.Ok;
      Default_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate (Compressed, Default_Status);
      Zlib_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Zlib_Header, Zlib_Status);
      GZip_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.GZip, GZip_Status);
      pragma Unreferenced (Zlib_Attempt, GZip_Attempt);
   begin
      Assert (Status = Zlib.Ok, Message & ": Deflate_Raw Dynamic status");
      Assert (Inflated_Status = Zlib.Ok, Message & ": raw inflate status");
      Assert_Same (Inflated, Input, Message & ": roundtrip");
      Assert (Default_Status = Zlib.Ok, Message & ": auto-detected by default Inflate");
      Assert_Same (Default_Attempt, Input, Message & ": default Inflate output");
      Assert (Zlib_Status /= Zlib.Ok, Message & ": rejected as zlib");
      Assert (GZip_Status /= Zlib.Ok, Message & ": rejected as gzip");
   end Assert_Roundtrip;

   procedure Test_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip (Empty, "empty raw dynamic");
   end Test_Empty;

   procedure Test_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip (Hello, "hello raw dynamic");
   end Test_Hello;

   procedure Test_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      Assert_Roundtrip (Input, "binary raw dynamic");
   end Test_Binary;

   procedure Test_Repeated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 4096);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (Character'Pos ('A') + (I mod 4));
      end loop;
      Assert_Roundtrip (Input, "repeated raw dynamic");
   end Test_Repeated;

   procedure Test_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path  : constant String := "raw_dynamic_input.bin";
      Output_Path : constant String := "raw_dynamic_output.deflate";
      Status      : Zlib.Status_Code := Zlib.Ok;
      Input       : constant Zlib.Byte_Array := Hello;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Input_Path, Input);

      Zlib.Deflate_Raw_File
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Mode        => Zlib.Dynamic,
         Status      => Status);

      Assert (Status = Zlib.Ok, "Deflate_Raw_File Dynamic must succeed");
      Assert_Roundtrip (Input, "raw dynamic file source payload");
      Assert_Same
        (Zlib.Inflate_With_Header (Read_File (Output_Path), Zlib.Raw_Deflate, Status),
         Input,
         "raw dynamic file output roundtrip");
      Assert (Status = Zlib.Ok, "raw dynamic file inflate status");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
   end Test_File;

   procedure Test_Wrapper_Strictness
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raw_Deflate_Status : Zlib.Status_Code := Zlib.Ok;
      Zlib_Wrapped_Status : Zlib.Status_Code := Zlib.Ok;
      GZip_Wrapped_Status : Zlib.Status_Code := Zlib.Ok;
      Raw_Output    : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Hello, Zlib.Dynamic, Raw_Deflate_Status);
      Raw_Status    : Zlib.Status_Code := Zlib.Ok;
      Zlib_Status   : Zlib.Status_Code := Zlib.Ok;
      GZip_Status   : Zlib.Status_Code := Zlib.Ok;
      Zlib_Output   : constant Zlib.Byte_Array :=
        Zlib.Deflate_Dynamic (Hello, Zlib_Wrapped_Status);
      Zlib_As_Raw   : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Zlib_Output, Zlib.Raw_Deflate, Zlib_Status);
      GZip_Output   : constant Zlib.Byte_Array :=
        Zlib.GZip (Hello, Zlib.Dynamic, GZip_Wrapped_Status);
      GZip_As_Raw   : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (GZip_Output, Zlib.Raw_Deflate, GZip_Status);
      Raw_Inflated  : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Raw_Output, Zlib.Raw_Deflate, Raw_Status);
      pragma Unreferenced (Zlib_As_Raw, GZip_As_Raw);
   begin
      Assert (Raw_Deflate_Status = Zlib.Ok, "raw wrapper strictness compression status");
      Assert (Zlib_Wrapped_Status = Zlib.Ok, "zlib wrapper strictness compression status");
      Assert (GZip_Wrapped_Status = Zlib.Ok, "gzip wrapper strictness compression status");
      Assert (Raw_Status = Zlib.Ok, "raw dynamic output accepted by Raw_Deflate inflate");
      Assert_Same (Raw_Inflated, Hello, "raw dynamic strictness roundtrip");
      Assert (Zlib_Status /= Zlib.Ok, "zlib dynamic output rejected by Raw_Deflate inflate");
      Assert (GZip_Status /= Zlib.Ok, "gzip dynamic output rejected by Raw_Deflate inflate");
   end Test_Wrapper_Strictness;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Empty'Access, "Deflate_Raw Dynamic empty roundtrips");
      Registration.Register_Routine (T, Test_Hello'Access, "Deflate_Raw Dynamic hello roundtrips");
      Registration.Register_Routine (T, Test_Binary'Access, "Deflate_Raw Dynamic binary roundtrips");
      Registration.Register_Routine (T, Test_Repeated'Access, "Deflate_Raw Dynamic repeated payload roundtrips");
      Registration.Register_Routine (T, Test_File'Access, "Deflate_Raw_File Dynamic roundtrips");
      Registration.Register_Routine
        (T, Test_Wrapper_Strictness'Access,
         "raw dynamic wrapper strictness");
   end Register_Tests;
end Zlib_Deflate_Raw_Dynamic_Tests;
