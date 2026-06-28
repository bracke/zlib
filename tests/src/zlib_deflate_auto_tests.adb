with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Auto_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Deflate Auto");
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

   function Same_Bytes
     (Left  : Zlib.Byte_Array;
      Right : Zlib.Byte_Array)
      return Boolean
   is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for I in Right'Range loop
         if Left (Left'First + (I - Right'First)) /= Right (I) then
            return False;
         end if;
      end loop;

      return True;
   end Same_Bytes;

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
                 (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
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
                    Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
               end loop;

               return Result;
            end;
         end;
      end;
   end Read_Bytes;

   procedure Inflate_Stream
     (Input       : Zlib.Byte_Array;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
      Result : Zlib.Byte_Array (1 .. Natural'Max (Expected'Length, 1));
      Last   : Natural := 0;

      procedure Copy_Output
        (Out_Data : Ada.Streams.Stream_Element_Array;
         Out_Last : Ada.Streams.Stream_Element_Offset)
      is
      begin
         if Out_Last = Before_First (Out_Data) then
            return;
         end if;

         for I in Out_Data'First .. Out_Last loop
            Last := Last + 1;
            Assert (Last <= Expected'Length, Message & ": produced too many bytes");
            Result (Last) := Zlib.Byte (Out_Data (I));
         end loop;
      end Copy_Output;
   begin
      Zlib.Inflate_Init (Filter);

      while Pos <= Input'Last loop
         declare
            Count    : constant Natural := Natural'Min (Chunk_Size, Input'Last - Pos + 1);
            In_Data  : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Input (Pos + I));
            end loop;

            Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
            Copy_Output (Out_Data, Out_Last);

            if In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
         end;

         for Guard in 1 .. 10_000 loop
            declare
               Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
            begin
               Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last);
               Copy_Output (Out_Data, Out_Last);
               exit when Out_Last = Before_First (Out_Data);
            end;
         end loop;
      end loop;

      for Guard in 1 .. 10_000 loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Copy_Output (Out_Data, Out_Last);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), Message & ": stream end");
      Zlib.Close (Filter);
      Assert (Last = Expected'Length, Message & ": decoded length");

      for I in Expected'Range loop
         Assert
           (Result (I - Expected'First + 1) = Expected (I),
            Message & ": decoded byte mismatch");
      end loop;
   end Inflate_Stream;

   procedure Assert_Auto_Roundtrip
     (Input   : Zlib.Byte_Array;
      Message : String)
   is
      Deflate_Status : Zlib.Status_Code;
      Inflate_Status : Zlib.Status_Code;
      Compressed     : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Auto, Deflate_Status);
      Output         : constant Zlib.Byte_Array :=
        Zlib.Inflate (Compressed, Inflate_Status);
   begin
      Assert (Deflate_Status = Zlib.Ok, Message & ": Deflate Auto status");
      Assert (Inflate_Status = Zlib.Ok, Message & ": Inflate status");
      Assert_Same (Output, Input, Message & ": one-shot roundtrip");
      Inflate_Stream (Compressed, Input, 3, 5, Message & ": streaming roundtrip");
   end Assert_Auto_Roundtrip;

   procedure Test_Auto_Empty_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      Assert_Auto_Roundtrip (Input, "Auto empty payload");
   end Test_Auto_Empty_Roundtrips;

   procedure Test_Auto_Hello_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   begin
      Assert_Auto_Roundtrip (Input, "Auto hello payload");
   end Test_Auto_Hello_Roundtrips;

   procedure Test_Auto_Binary_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 256);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I - 1);
      end loop;

      Assert_Auto_Roundtrip (Input, "Auto binary payload");
   end Test_Auto_Binary_Roundtrips;

   procedure Test_Auto_Git_Shaped_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
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
         14 => Zlib.Byte (Character'Pos (' ')),
         15 => Zlib.Byte (Character'Pos ('w')),
         16 => Zlib.Byte (Character'Pos ('o')),
         17 => Zlib.Byte (Character'Pos ('r')),
         18 => Zlib.Byte (Character'Pos ('l')),
         19 => Zlib.Byte (Character'Pos ('d')),
         20 => Zlib.Byte (Character'Pos (ASCII.LF))];
   begin
      Assert_Auto_Roundtrip (Input, "Auto Git-shaped payload");
   end Test_Auto_Git_Shaped_Roundtrips;

   procedure Test_Auto_Repeated_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 4096);
   begin
      for I in Input'Range loop
         case I mod 4 is
            when 0 => Input (I) := Zlib.Byte (Character'Pos ('A'));
            when 1 => Input (I) := Zlib.Byte (Character'Pos ('B'));
            when 2 => Input (I) := Zlib.Byte (Character'Pos ('C'));
            when others => Input (I) := Zlib.Byte (Character'Pos ('D'));
         end case;
      end loop;

      Assert_Auto_Roundtrip (Input, "Auto repeated payload");
   end Test_Auto_Repeated_Roundtrips;

   function Mode_Test_Input
      return Zlib.Byte_Array
   is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('m')),
         2 => Zlib.Byte (Character'Pos ('o')),
         3 => Zlib.Byte (Character'Pos ('d')),
         4 => Zlib.Byte (Character'Pos ('e')),
         5 => 0,
         6 => 16#FF#];
   end Mode_Test_Input;

   procedure Test_Stored_Mode_Equals_Deflate_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Mode_Test_Input;
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Stored, Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "Stored mode status");
      Assert (Status_B = Zlib.Ok, "Deflate_Stored status");
      Assert_Same (A, B, "Stored mode must equal Deflate_Stored");
   end Test_Stored_Mode_Equals_Deflate_Stored;

   procedure Test_Fixed_Mode_Equals_Deflate_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Mode_Test_Input;
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Fixed, Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "Fixed mode status");
      Assert (Status_B = Zlib.Ok, "Deflate_Fixed status");
      Assert_Same (A, B, "Fixed mode must equal Deflate_Fixed");
   end Test_Fixed_Mode_Equals_Deflate_Fixed;

   procedure Test_Dynamic_Mode_Equals_Deflate_Dynamic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Mode_Test_Input;
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Dynamic, Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Input, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "Dynamic mode status");
      Assert (Status_B = Zlib.Ok, "Deflate_Dynamic status");
      Assert_Same (A, B, "Dynamic mode must equal Deflate_Dynamic");
   end Test_Dynamic_Mode_Equals_Deflate_Dynamic;

   procedure Test_Default_Mode_Equals_Auto
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Mode_Test_Input;
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Status => Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "default Deflate status");
      Assert (Status_B = Zlib.Ok, "explicit Auto Deflate status");
      Assert_Same (A, B, "default Deflate mode must equal explicit Auto");
   end Test_Default_Mode_Equals_Auto;

   procedure Test_Auto_Chooses_A_Valid_Mode (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('v')),
         2 => Zlib.Byte (Character'Pos ('a')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('i')),
         5 => Zlib.Byte (Character'Pos ('d'))];
      Auto_Status    : Zlib.Status_Code;
      Stored_Status  : Zlib.Status_Code;
      Fixed_Status   : Zlib.Status_Code;
      Dynamic_Status : Zlib.Status_Code;
      Auto_Output    : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Auto_Status);
      Stored_Output  : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Stored_Status);
      Fixed_Output   : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Fixed_Status);
      Dynamic_Output : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Input, Dynamic_Status);

      Matches_Stored  : constant Boolean :=
        Stored_Status = Zlib.Ok
        and then Same_Bytes (Auto_Output, Stored_Output);
      Matches_Fixed   : constant Boolean :=
        Fixed_Status = Zlib.Ok
        and then Same_Bytes (Auto_Output, Fixed_Output);
      Matches_Dynamic : constant Boolean :=
        Dynamic_Status = Zlib.Ok
        and then Same_Bytes (Auto_Output, Dynamic_Output);
   begin
      Assert (Auto_Status = Zlib.Ok, "Auto valid-mode status");
      Assert
        (Matches_Stored or else Matches_Fixed or else Matches_Dynamic,
         "Auto output must match one successful explicit compression mode");
   end Test_Auto_Chooses_A_Valid_Mode;

   procedure Test_Auto_No_Larger_Than_Stored (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 128);
      Auto_Status   : Zlib.Status_Code;
      Stored_Status : Zlib.Status_Code;
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (Character'Pos ('x'));
      end loop;

      declare
         Auto_Output   : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Auto_Status);
         Stored_Output : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Stored_Status);
      begin
         Assert (Auto_Status = Zlib.Ok, "Auto representative status");
         Assert (Stored_Status = Zlib.Ok, "Stored representative status");
         Assert
           (Auto_Output'Length <= Stored_Output'Length,
            "Auto must not choose output larger than Stored when Stored succeeds");
      end;
   end Test_Auto_No_Larger_Than_Stored;

   procedure Test_Auto_Deterministic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('d')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('t')),
         4 => Zlib.Byte (Character'Pos ('e')),
         5 => Zlib.Byte (Character'Pos ('r')),
         6 => Zlib.Byte (Character'Pos ('m')),
         7 => Zlib.Byte (Character'Pos ('i')),
         8 => Zlib.Byte (Character'Pos ('n')),
         9 => Zlib.Byte (Character'Pos ('i')),
         10 => Zlib.Byte (Character'Pos ('s')),
         11 => Zlib.Byte (Character'Pos ('m'))];
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
      A : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status_A);
      B : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status_B);
   begin
      Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok, "Auto deterministic statuses");
      Assert_Same (A, B, "Auto output must be deterministic across repeated calls");
   end Test_Auto_Deterministic;

   procedure Test_Deflate_File_Auto_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_auto_plain.bin";
      Compressed_Path : constant String := "zlib_auto_plain.z";
      Inflated_Path   : constant String := "zlib_auto_plain.out";
      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('f')),
         2 => Zlib.Byte (Character'Pos ('i')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('e')),
         5 => 0,
         6 => 16#FF#];
      Status : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);

      Write_Bytes (Plain_Path, Input);
      Zlib.Deflate_File (Plain_Path, Compressed_Path, Zlib.Auto, Status);
      Assert (Status = Zlib.Ok, "Deflate_File Auto must succeed");

      Zlib.Inflate_File (Compressed_Path, Inflated_Path, Status);
      Assert (Status = Zlib.Ok, "Inflate_File must accept Deflate_File Auto output");

      declare
         Output : constant Zlib.Byte_Array := Read_Bytes (Inflated_Path);
      begin
         Assert_Same (Output, Input, "Deflate_File Auto roundtrip");
      end;

      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Deflate_File_Auto_Roundtrips;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Auto_Empty_Roundtrips'Access, "Deflate Auto empty roundtrips");
      Registration.Register_Routine (T, Test_Auto_Hello_Roundtrips'Access, "Deflate Auto hello roundtrips");
      Registration.Register_Routine (T, Test_Auto_Binary_Roundtrips'Access, "Deflate Auto binary roundtrips");
      Registration.Register_Routine
        (T, Test_Auto_Git_Shaped_Roundtrips'Access, "Deflate Auto Git-shaped payload roundtrips");
      Registration.Register_Routine
        (T, Test_Auto_Repeated_Roundtrips'Access, "Deflate Auto repeated payload roundtrips");
      Registration.Register_Routine
        (T, Test_Stored_Mode_Equals_Deflate_Stored'Access, "Deflate Stored mode equals Deflate_Stored");
      Registration.Register_Routine
        (T, Test_Fixed_Mode_Equals_Deflate_Fixed'Access, "Deflate Fixed mode equals Deflate_Fixed");
      Registration.Register_Routine
        (T, Test_Dynamic_Mode_Equals_Deflate_Dynamic'Access, "Deflate Dynamic mode equals Deflate_Dynamic");
      Registration.Register_Routine (T, Test_Default_Mode_Equals_Auto'Access, "Deflate default mode equals Auto");
      Registration.Register_Routine
        (T, Test_Auto_Chooses_A_Valid_Mode'Access, "Deflate Auto chooses a valid mode");
      Registration.Register_Routine
        (T, Test_Auto_No_Larger_Than_Stored'Access, "Deflate Auto is no larger than Stored");
      Registration.Register_Routine (T, Test_Auto_Deterministic'Access, "Deflate Auto output is deterministic");
      Registration.Register_Routine (T, Test_Deflate_File_Auto_Roundtrips'Access, "Deflate_File Auto roundtrips");
   end Register_Tests;

end Zlib_Deflate_Auto_Tests;
