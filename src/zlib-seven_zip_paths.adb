with Ada.Strings.Unbounded;
with Zlib.Native_Files;

package body Zlib.Seven_Zip_Paths
  with SPARK_Mode => On
is
   use type Zlib.Native_Files.File_Kind;

   package US renames Ada.Strings.Unbounded;

   function Entry_Name_Valid (Entry_Name : String) return Boolean is
   begin
      if Entry_Name'Length = 0 then
         return False;
      end if;

      for Ch of Entry_Name loop
         if Ch = Character'Val (0) then
            return False;
         end if;
      end loop;

      return True;
   end Entry_Name_Valid;

   function Entry_Names_Valid (Entry_Names : Text_Array) return Boolean
     with SPARK_Mode => Off
   is
   begin
      if Entry_Names'Length = 0 then
         return False;
      end if;

      for Offset in 0 .. Entry_Names'Length - 1 loop
         declare
            Entry_Name : constant String :=
              US.To_String (Entry_Names (Entry_Names'First + Offset));
         begin
            if not Entry_Name_Valid (Entry_Name) then
               return False;
            end if;

            if Offset > 0 then
               for Previous_Offset in 0 .. Offset - 1 loop
                  if Entry_Name =
                    US.To_String (Entry_Names (Entry_Names'First + Previous_Offset))
                  then
                     return False;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Entry_Names_Valid;

   function Safe_Output_Name (Entry_Name : String) return Boolean is
      type Segment_State is (Empty, Dot, Dot_Dot, Other);

      State : Segment_State := Empty;
   begin
      if Entry_Name'Length = 0
        or else Entry_Name (Entry_Name'First) = '/'
      then
         return False;
      end if;

      for Ch of Entry_Name loop
         case Ch is
            when '/' =>
               if State /= Other then
                  return False;
               end if;
               State := Empty;
            when Character'Val (0) | '\' | ':' =>
               return False;
            when '.' =>
               case State is
                  when Empty   => State := Dot;
                  when Dot     => State := Dot_Dot;
                  when Dot_Dot => State := Other;
                  when Other   => null;
               end case;
            when others =>
               State := Other;
         end case;
      end loop;

      return State = Other
        or else (State = Empty and then Entry_Name (Entry_Name'Last) = '/');
   end Safe_Output_Name;

   function Output_File_Writable (Output_Path : String) return Boolean
     with SPARK_Mode => Off
   is
   begin
      if Output_Path'Length = 0 then
         return False;
      end if;

      if Zlib.Native_Files.Exists (Output_Path)
        and then Zlib.Native_Files.Kind (Output_Path) = Zlib.Native_Files.Directory
      then
         return False;
      end if;

      declare
         Parent_Path : constant String :=
           Zlib.Native_Files.Containing_Directory (Output_Path);
      begin
         return not Zlib.Native_Files.Exists (Parent_Path)
           or else Zlib.Native_Files.Kind (Parent_Path) = Zlib.Native_Files.Directory;
      end;
   exception
      when others =>
         return False;
   end Output_File_Writable;

   function Input_Path_Readable (Input_Path : String) return Boolean
     with SPARK_Mode => Off
   is
   begin
      return Input_Path'Length > 0
        and then Zlib.Native_Files.Exists (Input_Path)
        and then Zlib.Native_Files.Kind (Input_Path) in
          Zlib.Native_Files.Ordinary_File | Zlib.Native_Files.Directory;
   exception
      when others =>
         return False;
   end Input_Path_Readable;

   function Input_Paths_Readable (Input_Paths : Text_Array) return Boolean
     with SPARK_Mode => Off
   is
   begin
      if Input_Paths'Length = 0 then
         return False;
      end if;

      for Input_Path_Text of Input_Paths loop
         if not Input_Path_Readable (US.To_String (Input_Path_Text)) then
            return False;
         end if;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Input_Paths_Readable;

   function Output_Directory_Writable (Output_Dir : String) return Boolean
     with SPARK_Mode => Off
   is
   begin
      if Output_Dir'Length = 0 then
         return False;
      end if;

      if Zlib.Native_Files.Exists (Output_Dir) then
         return Zlib.Native_Files.Kind (Output_Dir) = Zlib.Native_Files.Directory;
      end if;

      declare
         Parent_Path : constant String :=
           Zlib.Native_Files.Containing_Directory (Output_Dir);
      begin
         return not Zlib.Native_Files.Exists (Parent_Path)
           or else Zlib.Native_Files.Kind (Parent_Path) = Zlib.Native_Files.Directory;
      end;
   exception
      when others =>
         return False;
   end Output_Directory_Writable;

   function Output_Path
     (Output_Dir : String;
      Entry_Name : String) return String
     with SPARK_Mode => Off
   is
      Has_Separator : constant Boolean :=
        Output_Dir'Length > 0 and then Output_Dir (Output_Dir'Last) = '/';
      Separator_Length : constant Natural := (if Has_Separator then 0 else 1);
      Raw_Length : constant Natural :=
        Output_Dir'Length + Separator_Length + Entry_Name'Length;
      Raw : String (1 .. Raw_Length);
      Pos : Positive := Raw'First;
   begin
      for Ch of Output_Dir loop
         Raw (Pos) := Ch;
         Pos := Pos + 1;
      end loop;

      if not Has_Separator then
         Raw (Pos) := '/';
         Pos := Pos + 1;
      end if;

      for Ch of Entry_Name loop
         Raw (Pos) := Ch;
         Pos := Pos + 1;
      end loop;

      if Raw'Length > 1 and then Raw (Raw'Last) = '/' then
         return Raw (Raw'First .. Raw'Last - 1);
      end if;

      return Raw;
   end Output_Path;

end Zlib.Seven_Zip_Paths;
