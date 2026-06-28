with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Compression_Level_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib compression level API");
   end Name;

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

   function Binary_Input return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 37 + I / 3) mod 256);
      end loop;
      return Result;
   end Binary_Input;

   function Repeated_Input return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 4096);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte (Character'Pos ('A') + (I mod 4));
      end loop;
      return Result;
   end Repeated_Input;

   function Git_Shaped_Input return Zlib.Byte_Array is
   begin
      return
        [1  => Zlib.Byte (Character'Pos ('b')),
         2  => Zlib.Byte (Character'Pos ('l')),
         3  => Zlib.Byte (Character'Pos ('o')),
         4  => Zlib.Byte (Character'Pos ('b')),
         5  => Zlib.Byte (Character'Pos (' ')),
         6  => Zlib.Byte (Character'Pos ('1')),
         7  => Zlib.Byte (Character'Pos ('2')),
         8  => 0,
         9  => Zlib.Byte (Character'Pos ('h')),
         10 => Zlib.Byte (Character'Pos ('e')),
         11 => Zlib.Byte (Character'Pos ('l')),
         12 => Zlib.Byte (Character'Pos ('l')),
         13 => Zlib.Byte (Character'Pos ('o')),
         14 => Zlib.Byte (Character'Pos (ASCII.LF))];
   end Git_Shaped_Input;

   procedure Assert_Level_Roundtrip
     (Input   : Zlib.Byte_Array;
      Wrapper : Zlib.Header_Type;
      Level   : Zlib.Compression_Level;
      Message : String)
   is
   begin
      case Wrapper is
         when Zlib.GZip =>
            declare
               Compress_Status : Zlib.Status_Code := Zlib.Ok;
               Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
               Compressed      : constant Zlib.Byte_Array :=
                 Zlib.GZip (Input, Level, Compress_Status);
               Inflated        : constant Zlib.Byte_Array :=
                 Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Inflate_Status);
            begin
               Assert (Compress_Status = Zlib.Ok, Message & ": compression status");
               Assert (Inflate_Status = Zlib.Ok, Message & ": inflate status");
               Assert_Same (Inflated, Input, Message & ": roundtrip");
            end;

         when Zlib.Raw_Deflate =>
            declare
               Compress_Status : Zlib.Status_Code := Zlib.Ok;
               Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
               Compressed      : constant Zlib.Byte_Array :=
                 Zlib.Deflate_Raw (Input, Level, Compress_Status);
               Inflated        : constant Zlib.Byte_Array :=
                 Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Inflate_Status);
            begin
               Assert (Compress_Status = Zlib.Ok, Message & ": compression status");
               Assert (Inflate_Status = Zlib.Ok, Message & ": inflate status");
               Assert_Same (Inflated, Input, Message & ": roundtrip");
            end;

         when others =>
            declare
               Compress_Status : Zlib.Status_Code := Zlib.Ok;
               Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
               Compressed      : constant Zlib.Byte_Array :=
                 Zlib.Deflate (Input, Level, Compress_Status);
               Inflated        : constant Zlib.Byte_Array :=
                 Zlib.Inflate (Compressed, Inflate_Status);
            begin
               Assert (Compress_Status = Zlib.Ok, Message & ": compression status");
               Assert (Inflate_Status = Zlib.Ok, Message & ": inflate status");
               Assert_Same (Inflated, Input, Message & ": roundtrip");
            end;
      end case;
   end Assert_Level_Roundtrip;

   procedure Test_Level_Constants
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.Compression_Level'Image (Zlib.Compression_Level'First) = " 0",
              "Compression_Level first must be 0");
      Assert (Zlib.Compression_Level'Image (Zlib.Compression_Level'Last) = " 9",
              "Compression_Level last must be 9");
      Assert (Zlib.Compression_Level'Image (Zlib.Default_Level) = " 6",
              "Default_Level must be 6");
   end Test_Level_Constants;

   procedure Test_Representative_Levels_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Binary_Input;
   begin
      declare
         Levels : constant array (Positive range 1 .. 3) of Zlib.Compression_Level :=
           [1 => 0, 2 => 1, 3 => 6];
      begin
         for Level of Levels loop
            Assert_Level_Roundtrip (Input, Zlib.Zlib_Header, Level, "zlib level" & Level'Image);
            Assert_Level_Roundtrip (Input, Zlib.GZip, Level, "gzip level" & Level'Image);
            Assert_Level_Roundtrip (Input, Zlib.Raw_Deflate, Level, "raw level" & Level'Image);
         end loop;
      end;
   end Test_Representative_Levels_Roundtrip;

   procedure Test_All_Levels_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Level in Zlib.Compression_Level loop
         Assert_Level_Roundtrip (Binary_Input, Zlib.Zlib_Header, Level, "binary all levels" & Level'Image);
         Assert_Level_Roundtrip (Git_Shaped_Input, Zlib.GZip, Level, "Git-shaped all levels" & Level'Image);
         Assert_Level_Roundtrip (Repeated_Input, Zlib.Raw_Deflate, Level, "repeated all levels" & Level'Image);
      end loop;
   end Test_All_Levels_Roundtrip;

   procedure Test_Level_Zero_Equals_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Binary_Input;
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Compression_Level'(0), Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "level 0 Deflate status");
      Assert (Status_B = Zlib.Ok, "Deflate_Stored status");
      Assert_Same (A, B, "level 0 must equal stored zlib output");
   end Test_Level_Zero_Equals_Stored;

   procedure Test_Level_One_Equals_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Binary_Input;
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Compression_Level'(1), Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "level 1 Deflate status");
      Assert (Status_B = Zlib.Ok, "Deflate_Fixed status");
      Assert_Same (A, B, "level 1 must equal fixed zlib output");
   end Test_Level_One_Equals_Fixed;

   procedure Test_GZip_Metadata_Level_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Git_Shaped_Input;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Compress_Status : Zlib.Status_Code := Zlib.Ok;
      Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
   begin
      Zlib.Set_Name (Metadata, "level-one-shot.txt");
      Zlib.Set_Comment (Metadata, "one-shot compression level metadata");
      Zlib.Set_MTime (Metadata, 42);
      Zlib.Set_OS (Metadata, 3);
      Zlib.Set_Header_CRC (Metadata, True);

      declare
         Compressed : constant Zlib.Byte_Array :=
           Zlib.GZip (Input, Zlib.Default_Level, Metadata, Compress_Status);
         Inflated   : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Inflate_Status);
      begin
         Assert (Compress_Status = Zlib.Ok, "gzip metadata level compression status");
         Assert (Inflate_Status = Zlib.Ok, "gzip metadata level inflate status");
         Assert_Same (Inflated, Input, "gzip metadata level roundtrip");
      end;
   end Test_GZip_Metadata_Level_Roundtrip;

   procedure Test_Level_Output_Deterministic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Repeated_Input;
   begin
      for Level in Zlib.Compression_Level loop
         declare
            Status_A : Zlib.Status_Code;
            Status_B : Zlib.Status_Code;
            A : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Level, Status_A);
            B : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Level, Status_B);
         begin
            Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok,
                    "level deterministic statuses" & Level'Image);
            Assert_Same (A, B, "raw level deterministic output" & Level'Image);
         end;
      end loop;
   end Test_Level_Output_Deterministic;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Level_Constants'Access,
                                     "Compression_Level constants are stable");
      Registration.Register_Routine (T, Test_Representative_Levels_Roundtrip'Access,
                                     "representative levels roundtrip through every wrapper");
      Registration.Register_Routine (T, Test_All_Levels_Roundtrip'Access,
                                     "all levels roundtrip representative payloads");
      Registration.Register_Routine (T, Test_Level_Zero_Equals_Stored'Access,
                                     "level 0 maps to Stored");
      Registration.Register_Routine (T, Test_Level_One_Equals_Fixed'Access,
                                     "level 1 maps to Fixed");
      Registration.Register_Routine (T, Test_GZip_Metadata_Level_Roundtrip'Access,
                                     "gzip metadata level overload roundtrips");
      Registration.Register_Routine (T, Test_Level_Output_Deterministic'Access,
                                     "level outputs are deterministic");
   end Register_Tests;
end Zlib_Compression_Level_Tests;
