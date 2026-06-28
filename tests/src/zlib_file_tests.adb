with Ada.Directories;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_File_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib file API");
   end Name;

   procedure Delete_If_Exists
     (Path : String)
   is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Write_Bytes
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
               Buffer
                 (Ada.Streams.Stream_Element_Offset
                    (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;

            SIO.Write (File, Buffer);
         end;
      end if;

      SIO.Close (File);
   end Write_Bytes;

   function Read_Bytes
     (Path : String)
      return Zlib.Byte_Array
   is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);

      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);

            declare
               Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
            begin
               return Empty;
            end;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);

            declare
               Result : Zlib.Byte_Array (1 .. Size);
            begin
               for I in Result'Range loop
                  Result (I) :=
                    Zlib.Byte
                      (Buffer (Ada.Streams.Stream_Element_Offset (I)));
               end loop;

               return Result;
            end;
         end;
      end;
   end Read_Bytes;

   procedure Test_Deflate_Stored_File_Roundtrip_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_file_plain.txt";
      Compressed_Path : constant String := "zlib_file_plain.z";
      Inflated_Path   : constant String := "zlib_file_plain.out";

      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];

      Status : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);

      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_Stored_File
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Status      => Status);

      Assert
        (Status = Zlib.Ok,
         "Deflate_Stored_File must successfully write compressed file");

      Zlib.Inflate_File
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Status      => Status);

      Assert
        (Status = Zlib.Ok,
         "Inflate_File must successfully read Deflate_Stored_File output");

      declare
         Output : constant Zlib.Byte_Array := Read_Bytes (Inflated_Path);
      begin
         Assert
           (Output'Length = Input'Length,
            "file roundtrip output length must match input length");

         for I in Input'Range loop
            Assert
              (Output (I) = Input (I),
               "file roundtrip output byte mismatch");
         end loop;
      end;

      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Deflate_Stored_File_Roundtrip_Hello;

   procedure Test_Deflate_Fixed_File_Roundtrip_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_file_fixed_plain.txt";
      Compressed_Path : constant String := "zlib_file_fixed_plain.z";
      Inflated_Path   : constant String := "zlib_file_fixed_plain.out";

      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o')),
         6 => 0,
         7 => 16#FF#];

      Status : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);

      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_Fixed_File
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Status      => Status);

      Assert
        (Status = Zlib.Ok,
         "Deflate_Fixed_File must successfully write compressed file");

      Zlib.Inflate_File
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Status      => Status);

      Assert
        (Status = Zlib.Ok,
         "Inflate_File must successfully read Deflate_Fixed_File output");

      declare
         Output : constant Zlib.Byte_Array := Read_Bytes (Inflated_Path);
      begin
         Assert
           (Output'Length = Input'Length,
            "fixed file roundtrip output length must match input length");

         for I in Input'Range loop
            Assert
              (Output (I) = Input (I),
               "fixed file roundtrip output byte mismatch");
         end loop;
      end;

      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Deflate_Fixed_File_Roundtrip_Hello;

   procedure Test_Deflate_Dynamic_File_Roundtrip_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_file_dynamic_plain.txt";
      Compressed_Path : constant String := "zlib_file_dynamic_plain.z";
      Inflated_Path   : constant String := "zlib_file_dynamic_plain.out";

      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o')),
         6 => 0,
         7 => 16#FF#];

      Status : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);

      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_Dynamic_File
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Status      => Status);

      Assert
        (Status = Zlib.Ok,
         "Deflate_Dynamic_File must successfully write compressed file");

      Zlib.Inflate_File
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Status      => Status);

      Assert
        (Status = Zlib.Ok,
         "Inflate_File must successfully read Deflate_Dynamic_File output");

      declare
         Output : constant Zlib.Byte_Array := Read_Bytes (Inflated_Path);
      begin
         Assert
           (Output'Length = Input'Length,
            "dynamic file roundtrip output length must match input length");

         for I in Input'Range loop
            Assert
              (Output (I) = Input (I),
               "dynamic file roundtrip output byte mismatch");
         end loop;
      end;

      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Deflate_Dynamic_File_Roundtrip_Hello;

   procedure Test_Inflate_File_Missing_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
   begin
      Delete_If_Exists ("zlib_missing_input.z");
      Delete_If_Exists ("zlib_missing_output.bin");

      Zlib.Inflate_File
        (Input_Path  => "zlib_missing_input.z",
         Output_Path => "zlib_missing_output.bin",
         Status      => Status);

      Assert
        (Status = Zlib.Input_File_Error,
         "Inflate_File with missing input must report Input_File_Error");
   end Test_Inflate_File_Missing_Input;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Deflate_Stored_File_Roundtrip_Hello'Access,
         "Deflate_Stored_File then Inflate_File roundtrip hello");

      Registration.Register_Routine
        (T,
         Test_Deflate_Fixed_File_Roundtrip_Hello'Access,
         "Deflate_Fixed_File then Inflate_File roundtrip hello");

      Registration.Register_Routine
        (T,
         Test_Deflate_Dynamic_File_Roundtrip_Hello'Access,
         "Deflate_Dynamic_File then Inflate_File roundtrip hello");

      Registration.Register_Routine
        (T,
         Test_Inflate_File_Missing_Input'Access,
         "Inflate_File missing input reports Input_File_Error");
   end Register_Tests;

end Zlib_File_Tests;
