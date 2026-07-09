with Ada.Containers.Vectors;
with Ada.Directories;

package body Zlib.Seven_Zip_Volumes is

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Byte);

   function To_Byte_Array (Data : Byte_Vectors.Vector) return Byte_Array
   is
      Output : Byte_Array (1 .. Natural (Data.Length));
      Pos    : Natural := Output'First;
   begin
      for B of Data loop
         Output (Pos) := B;
         Pos := Pos + 1;
      end loop;

      return Output;
   end To_Byte_Array;

   function Suffix (N : Positive) return String
     with SPARK_Mode => On
   is
      Img : constant String := N'Image;
      Dig : constant String := Img (Img'First + 1 .. Img'Last);
   begin
      if Dig'Length >= 3 then
         return Dig;
      elsif Dig'Length = 2 then
         return "0" & Dig;
      else
         return "00" & Dig;
      end if;
   end Suffix;

   function Read
     (First_Volume_Path : String;
      Read_File         : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Status            : out Status_Code) return Byte_Array
   is
      Result : Byte_Vectors.Vector;
      Dot    : Natural := 0;
   begin
      Status := Input_File_Error;
      for I in reverse First_Volume_Path'Range loop
         if First_Volume_Path (I) = '.' then
            Dot := I;
            exit;
         end if;
      end loop;

      if Dot = 0 then
         return [1 .. 0 => 0];
      end if;

      declare
         Base : constant String :=
           First_Volume_Path (First_Volume_Path'First .. Dot - 1);
         N    : Positive := 1;
      begin
         loop
            declare
               VP : constant String := Base & "." & Suffix (N);
            begin
               exit when not Ada.Directories.Exists (VP);
               declare
                  RS : Status_Code := Ok;
                  B  : constant Byte_Array := Read_File (VP, RS);
               begin
                  if RS /= Ok then
                     Status := RS;
                     return [1 .. 0 => 0];
                  end if;

                  for X of B loop
                     Result.Append (X);
                  end loop;
               end;
            end;

            N := N + 1;
         end loop;
      end;

      if Result.Is_Empty then
         return [1 .. 0 => 0];
      end if;

      Status := Ok;
      return To_Byte_Array (Result);
   end Read;

   procedure Write
     (Archive     : Byte_Array;
      Base_Path   : String;
      Volume_Size : Positive;
      Write_File  : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Status      : out Status_Code)
   is
      N   : Positive := 1;
      Pos : Natural := Archive'First;
   begin
      Status := Ok;

      if Archive'Length = 0 then
         Status := Output_File_Error;
         return;
      end if;

      while Pos <= Archive'Last loop
         declare
            Last : constant Natural :=
              Natural'Min (Pos + Volume_Size - 1, Archive'Last);
            VP   : constant String := Base_Path & "." & Suffix (N);
            WS   : Status_Code := Ok;
         begin
            Write_File (VP, Archive (Pos .. Last), WS);
            if WS /= Ok then
               Status := WS;
               return;
            end if;

            Pos := Last + 1;
            N := N + 1;
         end;
      end loop;
   end Write;

   function Extract
     (First_Volume_Path : String;
      Entry_Name        : String;
      Password          : String;
      Read_File         : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Extract_Entry     : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Status        : out Status_Code) return Byte_Array;
      Extract_Entry_With_Password : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Status            : out Status_Code) return Byte_Array
   is
      Joined : constant Byte_Array :=
        Read (First_Volume_Path, Read_File, Status);
   begin
      if Status /= Ok then
         return [1 .. 0 => 0];
      end if;

      if Password = "" then
         return Extract_Entry (Joined, Entry_Name, Status);
      else
         return Extract_Entry_With_Password (Joined, Entry_Name, Password, Status);
      end if;
   end Extract;

end Zlib.Seven_Zip_Volumes;
