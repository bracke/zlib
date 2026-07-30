with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;

package body Zlib_Cab_Tests is
   package US renames Ada.Strings.Unbounded;

   use type Interfaces.Unsigned_64;
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;

   --  ---------------------------------------------------------------------
   --  A tiny growable byte buffer used to assemble cabinet fixtures.
   --  ---------------------------------------------------------------------
   type Byte_Buffer is record
      Data : Zlib.Byte_Array (0 .. 65_535) := [others => 0];
      Len  : Natural := 0;
   end record;

   procedure Put_U8 (B : in out Byte_Buffer; Value : Natural) is
   begin
      B.Data (B.Len) := Zlib.Byte (Value mod 256);
      B.Len := B.Len + 1;
   end Put_U8;

   procedure Put_U16 (B : in out Byte_Buffer; Value : Natural) is
   begin
      Put_U8 (B, Value mod 256);
      Put_U8 (B, (Value / 256) mod 256);
   end Put_U16;

   procedure Put_U32 (B : in out Byte_Buffer; Value : Natural) is
   begin
      Put_U16 (B, Value mod 65_536);
      Put_U16 (B, (Value / 65_536) mod 65_536);
   end Put_U32;

   procedure Put_Bytes (B : in out Byte_Buffer; Bytes : Zlib.Byte_Array) is
   begin
      for Byte of Bytes loop
         B.Data (B.Len) := Byte;
         B.Len := B.Len + 1;
      end loop;
   end Put_Bytes;

   procedure Put_Name (B : in out Byte_Buffer; Name : String) is
   begin
      for C of Name loop
         Put_U8 (B, Character'Pos (C));
      end loop;
      Put_U8 (B, 0);   --  NUL terminator
   end Put_Name;

   function To_Bytes (S : String) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (0 .. S'Length - 1);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte (Character'Pos (S (S'First + I)));
      end loop;
      return Result;
   end To_Bytes;

   function Slice (B : Byte_Buffer) return Zlib.Byte_Array is
     (B.Data (0 .. B.Len - 1));

   --  ---------------------------------------------------------------------
   --  Assemble a single-folder cabinet with two stored/MSZIP members whose
   --  contents concatenate into one CFDATA block.
   --  ---------------------------------------------------------------------
   Name_1    : constant String := "hello.txt";
   Content_1 : constant String := "Hello, world!";
   Name_2    : constant String := "docs/readme";
   Content_2 : constant String := "cabinet";

   function Build_Cab (Use_MSZIP : Boolean) return Zlib.Byte_Array is
      Payload : constant Zlib.Byte_Array := To_Bytes (Content_1 & Content_2);

      Block_Status : Zlib.Status_Code := Zlib.Ok;
      Deflated     : constant Zlib.Byte_Array :=
        (if Use_MSZIP
         then Zlib.Deflate_Raw (Payload, Status => Block_Status)
         else [1 .. 0 => 0]);

      --  The CFDATA payload: 'CK' + raw Deflate for MSZIP, verbatim for Store.
      Block_Data : constant Zlib.Byte_Array :=
        (if Use_MSZIP
         then [Zlib.Byte (Character'Pos ('C')), Zlib.Byte (Character'Pos ('K'))]
              & Deflated
         else Payload);

      Rec_1_Size : constant Natural := 16 + Name_1'Length + 1;
      Rec_2_Size : constant Natural := 16 + Name_2'Length + 1;
      Files_Off  : constant Natural := 36 + 8;                 --  after folder
      Data_Off   : constant Natural := Files_Off + Rec_1_Size + Rec_2_Size;
      Total      : constant Natural := Data_Off + 8 + Block_Data'Length;

      B : Byte_Buffer;
   begin
      pragma Assert (Block_Status = Zlib.Ok);
      --  CFHEADER (36 bytes).
      Put_U8 (B, Character'Pos ('M'));
      Put_U8 (B, Character'Pos ('S'));
      Put_U8 (B, Character'Pos ('C'));
      Put_U8 (B, Character'Pos ('F'));
      Put_U32 (B, 0);                       --  reserved1
      Put_U32 (B, Total);                   --  cbCabinet
      Put_U32 (B, 0);                       --  reserved2
      Put_U32 (B, Files_Off);               --  coffFiles
      Put_U32 (B, 0);                       --  reserved3
      Put_U8 (B, 3);                        --  versionMinor
      Put_U8 (B, 1);                        --  versionMajor
      Put_U16 (B, 1);                       --  cFolders
      Put_U16 (B, 2);                       --  cFiles
      Put_U16 (B, 0);                       --  flags
      Put_U16 (B, 0);                       --  setID
      Put_U16 (B, 0);                       --  iCabinet

      --  CFFOLDER (8 bytes).
      Put_U32 (B, Data_Off);                --  coffCabStart
      Put_U16 (B, 1);                       --  cCFData
      Put_U16 (B, (if Use_MSZIP then 1 else 0));  --  typeCompress

      --  CFFILE records.
      Put_U32 (B, Content_1'Length);        --  cbFile
      Put_U32 (B, 0);                       --  uoffFolderStart
      Put_U16 (B, 0);                       --  iFolder
      Put_U16 (B, 0);                       --  date
      Put_U16 (B, 0);                       --  time
      Put_U16 (B, 0);                       --  attribs
      Put_Name (B, Name_1);

      Put_U32 (B, Content_2'Length);        --  cbFile
      Put_U32 (B, Content_1'Length);        --  uoffFolderStart
      Put_U16 (B, 0);                       --  iFolder
      Put_U16 (B, 0);                       --  date
      Put_U16 (B, 0);                       --  time
      Put_U16 (B, 0);                       --  attribs
      Put_Name (B, Name_2);

      --  CFDATA block.
      Put_U32 (B, 0);                       --  csum (unchecked)
      Put_U16 (B, Block_Data'Length);       --  cbData
      Put_U16 (B, Payload'Length);          --  cbUncomp
      Put_Bytes (B, Block_Data);

      return Slice (B);
   end Build_Cab;

   --  ---------------------------------------------------------------------
   --  Routines.
   --  ---------------------------------------------------------------------
   procedure Check_List_And_Extract (Image : Zlib.Byte_Array) is
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_CAB_Entries (Image, Status);
      begin
         Assert (Status = Zlib.Ok, "List_CAB_Entries status not Ok");
         Assert (Entries'Length = 2, "expected two catalogued members");
         Assert (US.To_String (Entries (Entries'First).Name) = Name_1,
                 "first member name mismatch");
         Assert (US.To_String (Entries (Entries'First + 1).Name) = Name_2,
                 "second member name mismatch");
         Assert
           (Entries (Entries'First).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content_1'Length),
            "first member size mismatch");
         Assert
           (Entries (Entries'First + 1).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content_2'Length),
            "second member size mismatch");
      end;

      declare
         S1 : Zlib.Status_Code := Zlib.Invalid_Header;
         S2 : Zlib.Status_Code := Zlib.Invalid_Header;
         B1 : constant Zlib.Byte_Array := Zlib.Extract_CAB (Image, Name_1, S1);
         B2 : constant Zlib.Byte_Array := Zlib.Extract_CAB (Image, Name_2, S2);
      begin
         Assert (S1 = Zlib.Ok, "Extract_CAB first status not Ok");
         Assert (S2 = Zlib.Ok, "Extract_CAB second status not Ok");
         Assert (B1 = To_Bytes (Content_1), "first member payload mismatch");
         Assert (B2 = To_Bytes (Content_2), "second member payload mismatch");
      end;
   end Check_List_And_Extract;

   procedure Test_Store_List_And_Extract (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_List_And_Extract (Build_Cab (Use_MSZIP => False));
   end Test_Store_List_And_Extract;

   procedure Test_MSZIP_List_And_Extract (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_List_And_Extract (Build_Cab (Use_MSZIP => True));
   end Test_MSZIP_List_And_Extract;

   procedure Test_Missing_Entry (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Image  : constant Zlib.Byte_Array := Build_Cab (Use_MSZIP => True);
      Status : Zlib.Status_Code := Zlib.Ok;
      Bytes  : constant Zlib.Byte_Array :=
        Zlib.Extract_CAB (Image, "no-such-file", Status);
   begin
      Assert (Bytes'Length = 0, "missing entry should yield no bytes");
      Assert (Status /= Zlib.Ok, "missing entry should not report Ok");
   end Test_Missing_Entry;

   procedure Test_Bad_Magic_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Image  : Zlib.Byte_Array := Build_Cab (Use_MSZIP => False);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Image (Image'First) := 16#00#;   --  corrupt 'M' of MSCF
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_CAB_Entries (Image, Status);
      begin
         Assert (Entries'Length = 0, "bad magic should yield no entries");
         Assert (Status = Zlib.Invalid_Header,
                 "bad magic should be Invalid_Header");
      end;
   end Test_Bad_Magic_Rejected;

   procedure Test_Unsupported_Layout_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Image  : Zlib.Byte_Array := Build_Cab (Use_MSZIP => False);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      --  cFolders lives at header offset 26; force a multi-folder cabinet.
      Image (Image'First + 26) := 2;
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_CAB_Entries (Image, Status);
      begin
         Assert (Entries'Length = 0, "multi-folder should yield no entries");
         Assert (Status = Zlib.Unsupported_Method,
                 "multi-folder should be Unsupported_Method");
      end;
   end Test_Unsupported_Layout_Rejected;

   procedure Test_Truncated_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Full   : constant Zlib.Byte_Array := Build_Cab (Use_MSZIP => True);
      Image  : constant Zlib.Byte_Array :=
        Full (Full'First .. Full'First + Full'Length / 2);
      Status : Zlib.Status_Code := Zlib.Ok;
      Bytes  : constant Zlib.Byte_Array :=
        Zlib.Extract_CAB (Image, Name_2, Status);
   begin
      Assert (Bytes'Length = 0, "truncated cabinet should yield no bytes");
      Assert (Status /= Zlib.Ok, "truncated cabinet should not report Ok");
   end Test_Truncated_Rejected;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib Microsoft Cabinet reader");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Store_List_And_Extract'Access,
         "stored cabinet catalogue and extraction");
      Register_Routine
        (T, Test_MSZIP_List_And_Extract'Access,
         "MSZIP cabinet catalogue and Deflate extraction");
      Register_Routine
        (T, Test_Missing_Entry'Access,
         "extracting an absent member fails closed");
      Register_Routine
        (T, Test_Bad_Magic_Rejected'Access,
         "a non-MSCF signature is rejected");
      Register_Routine
        (T, Test_Unsupported_Layout_Rejected'Access,
         "a multi-folder cabinet is rejected as unsupported");
      Register_Routine
        (T, Test_Truncated_Rejected'Access,
         "a truncated cabinet fails closed");
   end Register_Tests;

end Zlib_Cab_Tests;
