with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Directories;
with GNAT.OS_Lib;
with Zlib.Seven_Zip_Numbers;

package body Zlib.Seven_Zip_Properties is
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Kind;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type GNAT.OS_Lib.OS_Time;

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

   procedure Append_Bytes
     (Output : in out Byte_Vectors.Vector;
      Data   : Byte_Array) is
   begin
      for B of Data loop
         Output.Append (B);
      end loop;
   end Append_Bytes;

   procedure Append_U32_LE
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_32)
   is
      V : Interfaces.Unsigned_32 := Value;
   begin
      for I in 1 .. 4 loop
         pragma Unreferenced (I);
         Output.Append (Byte (V mod 256));
         V := V / 256;
      end loop;
   end Append_U32_LE;

   procedure Append_U64_LE
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_64)
   is
      V : Interfaces.Unsigned_64 := Value;
   begin
      for I in 1 .. 8 loop
         pragma Unreferenced (I);
         Output.Append (Byte (V mod 256));
         V := V / 256;
      end loop;
   end Append_U64_LE;

   function Bit_Is_Set
     (Data  : Byte_Array;
      First : Natural;
      Index : Natural) return Boolean
     with SPARK_Mode => On
   is
      Offset : Natural;
      Byte_Pos : Natural;
      Mask     : Byte;
   begin
      if Index = 0 then
         return False;
      end if;

      Offset := (Index - 1) / 8;
      if First > Natural'Last - Offset then
         return False;
      end if;

      Byte_Pos := First + Offset;
      if Byte_Pos not in Data'Range then
         return False;
      end if;

      Mask :=
        Byte
          (Interfaces.Shift_Right
             (Interfaces.Unsigned_8'(16#80#), (Index - 1) mod 8));
      return (Data (Byte_Pos) and Mask) /= 0;
   end Bit_Is_Set;

   function U64_LE
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_64
     with SPARK_Mode => On
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      if Pos not in Data'Range
        or else Pos > Natural'Last - 7
        or else Pos + 7 > Data'Last
      then
         return 0;
      end if;

      for I in 0 .. 7 loop
         Result :=
           Result
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
      end loop;
      return Result;
   end U64_LE;

   function U32_LE
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
     with SPARK_Mode => On
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      if Pos not in Data'Range
        or else Pos > Natural'Last - 3
        or else Pos + 3 > Data'Last
      then
         return 0;
      end if;

      for I in 0 .. 3 loop
         Result :=
           Result
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_32 (Data (Pos + I)), 8 * I);
      end loop;
      return Result;
   end U32_LE;

   function Read_File_Time_Property
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Target     : Natural;
      Has_Time   : out Boolean;
      Time       : out Interfaces.Unsigned_64) return Boolean
   is
      Last        : constant Natural := First + Count - 1;
      Pos         : Natural := First;
      All_Defined : Boolean;
      Defined_Pos : Natural := 0;
   begin
      Has_Time := False;
      Time := 0;

      if Count = 0
        or else File_Count = 0
        or else Target not in 1 .. File_Count
      then
         return False;
      end if;

      All_Defined := Data (Pos) /= 0;
      Pos := Pos + 1;

      if not All_Defined then
         if Count < 1 + (File_Count + 7) / 8 then
            return False;
         end if;
         Defined_Pos := Pos;
         Pos := Pos + (File_Count + 7) / 8;
      end if;

      if Pos > Last or else Data (Pos) /= 0 then
         return False;
      end if;
      Pos := Pos + 1;

      for I in 1 .. File_Count loop
         declare
            Defined : constant Boolean :=
              All_Defined or else Bit_Is_Set (Data, Defined_Pos, I);
         begin
            if Defined then
               if Pos > Last or else Last - Pos + 1 < 8 then
                  return False;
               end if;

               if I = Target then
                  Has_Time := True;
                  Time := U64_LE (Data, Pos);
               end if;

               Pos := Pos + 8;
            elsif I = Target then
               Has_Time := False;
               Time := 0;
            end if;
         end;
      end loop;

      return Pos = Last + 1;
   exception
      when others =>
         Has_Time := False;
         Time := 0;
         return False;
   end Read_File_Time_Property;

   function Read_U32_Property
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Target     : Natural;
      Has_Value  : out Boolean;
      Value      : out Interfaces.Unsigned_32) return Boolean
   is
      Last        : constant Natural := First + Count - 1;
      Pos         : Natural := First;
      All_Defined : Boolean;
      Defined_Pos : Natural := 0;
      Defined_Count : Natural := 0;
   begin
      Has_Value := False;
      Value := 0;

      if Count = 0
        or else File_Count = 0
        or else Target not in 1 .. File_Count
      then
         return False;
      end if;

      All_Defined := Data (Pos) /= 0;
      Pos := Pos + 1;

      if not All_Defined then
         if Count < 1 + (File_Count + 7) / 8 then
            return False;
         end if;
         Defined_Pos := Pos;
         Pos := Pos + (File_Count + 7) / 8;
      end if;

      for I in 1 .. File_Count loop
         if All_Defined or else Bit_Is_Set (Data, Defined_Pos, I) then
            Defined_Count := Defined_Count + 1;
         end if;
      end loop;

      if Pos <= Last
        and then Data (Pos) = 0
        and then Last - Pos = 4 * Defined_Count
      then
         Pos := Pos + 1;
      end if;

      for I in 1 .. File_Count loop
         declare
            Defined : constant Boolean :=
              All_Defined or else Bit_Is_Set (Data, Defined_Pos, I);
         begin
            if Defined then
               if Pos > Last or else Last - Pos + 1 < 4 then
                  return False;
               end if;

               if I = Target then
                  Has_Value := True;
                  Value := U32_LE (Data, Pos);
               end if;

               Pos := Pos + 4;
            elsif I = Target then
               Has_Value := False;
               Value := 0;
            end if;
         end;
      end loop;

      return Pos = Last + 1;
   exception
      when others =>
         Has_Value := False;
         Value := 0;
         return False;
   end Read_U32_Property;

   function Name_Index
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Entry_Name : String;
      Index      : out Natural) return Boolean
   is
      Last  : constant Natural := First + Count - 1;
      Pos   : Natural := First;
      Found : Boolean := False;
   begin
      Index := 0;

      if Count = 0 or else File_Count = 0 or else Data (Pos) /= 0 then
         return False;
      end if;
      Pos := Pos + 1;

      for File_Index in 1 .. File_Count loop
         declare
            Match    : Boolean := True;
            Name_Pos : Natural := Entry_Name'First;
         begin
            loop
               if Pos + 1 > Last then
                  return False;
               end if;

               exit when Data (Pos) = 0 and then Data (Pos + 1) = 0;

               if Name_Pos > Entry_Name'Last
                 or else Data (Pos) /=
                   Byte (Character'Pos (Entry_Name (Name_Pos)) mod 256)
                 or else Data (Pos + 1) /=
                   Byte (Character'Pos (Entry_Name (Name_Pos)) / 256)
               then
                  Match := False;
               end if;

               if Name_Pos <= Entry_Name'Last then
                  Name_Pos := Name_Pos + 1;
               end if;

               Pos := Pos + 2;
            end loop;

            if Match and then Name_Pos = Entry_Name'Last + 1 then
               if Found then
                  Index := 0;
                  return False;
               end if;
               Found := True;
               Index := File_Index;
            end if;

            Pos := Pos + 2;
         end;
      end loop;

      return Pos = Last + 1 and then Found;
   exception
      when others =>
      Index := 0;
      return False;
   end Name_Index;

   function Read_Target_Entry
     (Data        : Byte_Array;
      Pos         : in out Natural;
      Last        : Natural;
      File_Count  : Natural;
      Entry_Name  : String;
      Target      : out Files_Info_Target;
      Stream_Count : out Natural) return Boolean
   is
      type Boolean_Array is array (Positive range <>) of Boolean;
      type U32_Array is array (Positive range <>) of Interfaces.Unsigned_32;
      type U64_Array is array (Positive range <>) of Interfaces.Unsigned_64;

      File_Has_Stream     : Boolean_Array (1 .. File_Count) := [others => True];
      File_Is_Directory   : Boolean_Array (1 .. File_Count) := [others => False];
      File_Has_MTime      : Boolean_Array (1 .. File_Count) := [others => False];
      File_MTime          : U64_Array (1 .. File_Count) := [others => 0];
      File_Has_Attributes : Boolean_Array (1 .. File_Count) := [others => False];
      File_Attributes     : U32_Array (1 .. File_Count) := [others => 0];
      Empty_Count         : Natural := 0;
      Name_Found          : Boolean := False;
      Prop_Id             : Byte := 0;
      Prop_Size_U64       : Interfaces.Unsigned_64 := 0;
   begin
      Target := (others => <>);
      Stream_Count := 0;

      if File_Count = 0 then
         return False;
      end if;

      loop
         if Pos > Last then
            return False;
         end if;

         Prop_Id := Data (Pos);
         Pos := Pos + 1;
         exit when Prop_Id = 0;

         if not Zlib.Seven_Zip_Numbers.Read_Number
           (Data, Pos, Last, Prop_Size_U64)
           or else Prop_Size_U64 > Interfaces.Unsigned_64 (Natural'Last)
           or else Prop_Size_U64 > Interfaces.Unsigned_64 (Last - Pos + 1)
         then
            return False;
         end if;

         declare
            Prop_Size  : constant Natural := Natural (Prop_Size_U64);
            Prop_First : constant Natural := Pos;
            Prop_Last  : constant Natural :=
              (if Prop_Size = 0 then Prop_First - 1 else Prop_First + Prop_Size - 1);
         begin
            case Prop_Id is
               when 16#11# =>
                  if Prop_Size = 0
                    or else Prop_Size mod 2 = 0
                    or else Prop_Size < 1 + 2 * File_Count
                    or else not Name_Index
                      (Data, Prop_First, Prop_Size, File_Count, Entry_Name,
                       Target.File_Index)
                  then
                     return False;
                  end if;
                  Name_Found := True;

               when 16#0E# =>
                  if Prop_Size < (File_Count + 7) / 8 then
                     return False;
                  end if;

                  Empty_Count := 0;
                  for I in 1 .. File_Count loop
                     if Bit_Is_Set (Data, Prop_First, I) then
                        File_Has_Stream (I) := False;
                        File_Is_Directory (I) := True;
                        Empty_Count := Empty_Count + 1;
                     else
                        File_Has_Stream (I) := True;
                        File_Is_Directory (I) := False;
                     end if;
                  end loop;

               when 16#0F# =>
                  if Empty_Count = 0
                    or else Prop_Size < (Empty_Count + 7) / 8
                  then
                     return False;
                  end if;

                  declare
                     Empty_Index : Natural := 0;
                  begin
                     for I in 1 .. File_Count loop
                        if not File_Has_Stream (I) then
                           Empty_Index := Empty_Index + 1;
                           File_Is_Directory (I) :=
                             not Bit_Is_Set (Data, Prop_First, Empty_Index);
                        end if;
                     end loop;
                  end;

               when 16#10# =>
                  for I in 1 .. File_Count loop
                     if Bit_Is_Set (Data, Prop_First, I) then
                        return False;
                     end if;
                  end loop;

               when 16#14# =>
                  for I in 1 .. File_Count loop
                     if not Read_File_Time_Property
                       (Data, Prop_First, Prop_Size, File_Count, I,
                        File_Has_MTime (I), File_MTime (I))
                     then
                        return False;
                     end if;
                  end loop;

               when 16#15# =>
                  for I in 1 .. File_Count loop
                     if not Read_U32_Property
                       (Data, Prop_First, Prop_Size, File_Count, I,
                        File_Has_Attributes (I), File_Attributes (I))
                     then
                        return False;
                     end if;
                  end loop;

               when others =>
                  null;
            end case;

            Pos := Prop_Last + 1;
         end;
      end loop;

      if not Name_Found or else Target.File_Index = 0 then
         return False;
      end if;

      Target.Has_Stream := File_Has_Stream (Target.File_Index);
      Target.Is_Directory := File_Is_Directory (Target.File_Index);
      Target.Metadata.Is_Directory := Target.Is_Directory;
      Target.Metadata.Has_Modification_Time :=
        File_Has_MTime (Target.File_Index);
      Target.Metadata.Modification_Time := File_MTime (Target.File_Index);
      Target.Metadata.Has_Windows_Attributes :=
        File_Has_Attributes (Target.File_Index);
      Target.Metadata.Windows_Attributes := File_Attributes (Target.File_Index);

      for I in 1 .. File_Count loop
         if File_Has_Stream (I) then
            Stream_Count := Stream_Count + 1;
            if I = Target.File_Index then
               Target.Stream_Index := Stream_Count;
            end if;
         end if;
      end loop;

      return True;
   exception
      when others =>
         Target := (others => <>);
         Stream_Count := 0;
         return False;
   end Read_Target_Entry;

   function Metadata_Image (Metadata : Seven_Zip_Entry_Metadata) return Byte_Array
   is
      Header : Byte_Vectors.Vector;
   begin
      if Metadata.Has_Modification_Time then
         Header.Append (16#14#); --  MTime
         Append_Bytes (Header, Zlib.Seven_Zip_Numbers.Encode_Number (10));
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         Append_U64_LE (Header, Metadata.Modification_Time);
      end if;

      if Metadata.Has_Windows_Attributes then
         Header.Append (16#15#); --  WinAttributes
         Append_Bytes (Header, Zlib.Seven_Zip_Numbers.Encode_Number (6));
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         Append_U32_LE (Header, Metadata.Windows_Attributes);
      end if;

      return To_Byte_Array (Header);
   end Metadata_Image;

   function Metadata_Image (Metadata : Entry_Metadata_Array) return Byte_Array
   is
      Header              : Byte_Vectors.Vector;
      All_Have_MTime      : Boolean := Metadata'Length > 0;
      All_Have_Attributes : Boolean := Metadata'Length > 0;
   begin
      for Item of Metadata loop
         All_Have_MTime :=
           All_Have_MTime and then Item.Has_Modification_Time;
         All_Have_Attributes :=
           All_Have_Attributes and then Item.Has_Windows_Attributes;
      end loop;

      if All_Have_MTime then
         Header.Append (16#14#); --  MTime
         Append_Bytes
           (Header,
            Zlib.Seven_Zip_Numbers.Encode_Number
              (Interfaces.Unsigned_64 (2 + 8 * Metadata'Length)));
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         for Item of Metadata loop
            Append_U64_LE (Header, Item.Modification_Time);
         end loop;
      end if;

      if All_Have_Attributes then
         Header.Append (16#15#); --  WinAttributes
         Append_Bytes
           (Header,
            Zlib.Seven_Zip_Numbers.Encode_Number
              (Interfaces.Unsigned_64 (2 + 4 * Metadata'Length)));
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         for Item of Metadata loop
            Append_U32_LE (Header, Item.Windows_Attributes);
         end loop;
      end if;

      return To_Byte_Array (Header);
   end Metadata_Image;

   function Leap_Year (Year : Natural) return Boolean
     with SPARK_Mode => On
   is
   begin
      return (Year mod 4 = 0 and then Year mod 100 /= 0)
        or else Year mod 400 = 0;
   end Leap_Year;

   function Filetime_To_OS_Time
     (File_Time : Interfaces.Unsigned_64;
      OS_Time   : out GNAT.OS_Lib.OS_Time) return Boolean
   is
      Ticks_Per_Second : constant Interfaces.Unsigned_64 := 10_000_000;
      Unix_Epoch_Delta : constant Interfaces.Unsigned_64 := 11_644_473_600;
      Seconds          : Interfaces.Unsigned_64;
      Days             : Natural;
      Seconds_Of_Day   : Natural;
      Year             : Natural := 1970;
      Month            : Natural := 1;
      Day              : Natural;
      Month_Lengths    : constant array (1 .. 12) of Natural :=
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
   begin
      OS_Time := GNAT.OS_Lib.Invalid_Time;
      Seconds := File_Time / Ticks_Per_Second;
      if Seconds < Unix_Epoch_Delta then
         return False;
      end if;

      Seconds := Seconds - Unix_Epoch_Delta;
      if Seconds > Interfaces.Unsigned_64 (Natural'Last) then
         return False;
      end if;

      Days := Natural (Seconds / 86_400);
      Seconds_Of_Day := Natural (Seconds mod 86_400);

      loop
         declare
            Year_Days : constant Natural :=
              (if Leap_Year (Year) then 366 else 365);
         begin
            exit when Days < Year_Days;
            Days := Days - Year_Days;
            Year := Year + 1;
            if Year > GNAT.OS_Lib.Year_Type'Last then
               return False;
            end if;
         end;
      end loop;

      loop
         declare
            Month_Days : constant Natural :=
              (if Month = 2 and then Leap_Year (Year)
               then 29
               else Month_Lengths (Month));
         begin
            exit when Days < Month_Days;
            Days := Days - Month_Days;
            Month := Month + 1;
         end;
      end loop;

      Day := Days + 1;
      OS_Time :=
        GNAT.OS_Lib.GM_Time_Of
          (GNAT.OS_Lib.Year_Type (Year),
           GNAT.OS_Lib.Month_Type (Month),
           GNAT.OS_Lib.Day_Type (Day),
           GNAT.OS_Lib.Hour_Type (Seconds_Of_Day / 3_600),
           GNAT.OS_Lib.Minute_Type ((Seconds_Of_Day / 60) mod 60),
           GNAT.OS_Lib.Second_Type (Seconds_Of_Day mod 60));
      return OS_Time /= GNAT.OS_Lib.Invalid_Time;
   exception
      when others =>
         OS_Time := GNAT.OS_Lib.Invalid_Time;
         return False;
   end Filetime_To_OS_Time;

   function Source_Metadata
     (Input_Path : String) return Seven_Zip_Entry_Metadata
   is
      Unix_Epoch          : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1, 0.0);
      Filetime_Unix_Epoch : constant Interfaces.Unsigned_64 :=
        116_444_736_000_000_000;
      Ticks_Per_Second    : constant Long_Long_Float := 10_000_000.0;
      Metadata            : Seven_Zip_Entry_Metadata :=
        No_Seven_Zip_Entry_Metadata;
      Is_Directory        : constant Boolean :=
        Ada.Directories.Kind (Input_Path) = Ada.Directories.Directory;
      Seconds             : Duration;
      Ticks               : Interfaces.Unsigned_64 := 0;
   begin
      Metadata.Is_Directory := Is_Directory;
      Seconds := Ada.Directories.Modification_Time (Input_Path) - Unix_Epoch;
      Metadata.Has_Modification_Time := True;

      if Seconds >= 0.0 then
         Ticks :=
           Interfaces.Unsigned_64
             (Long_Long_Integer (Long_Long_Float (Seconds) * Ticks_Per_Second));
         Metadata.Modification_Time := Filetime_Unix_Epoch + Ticks;
      else
         Ticks :=
           Interfaces.Unsigned_64
             (Long_Long_Integer
                (Long_Long_Float (-Seconds) * Ticks_Per_Second));
         if Ticks <= Filetime_Unix_Epoch then
            Metadata.Modification_Time := Filetime_Unix_Epoch - Ticks;
         else
            Metadata.Has_Modification_Time := False;
         end if;
      end if;

      Metadata.Has_Windows_Attributes := True;
      Metadata.Windows_Attributes :=
        (if Is_Directory then 16#0000_0010# else 16#0000_0020#);
      if not GNAT.OS_Lib.Is_Owner_Writable_File (Input_Path) then
         Metadata.Windows_Attributes :=
           Metadata.Windows_Attributes or 16#0000_0001#;
      end if;

      return Metadata;
   exception
      when others =>
         return No_Seven_Zip_Entry_Metadata;
   end Source_Metadata;

   procedure Apply_Metadata
     (Path     : String;
      Metadata : Seven_Zip_Entry_Metadata)
   is
      OS_Time : GNAT.OS_Lib.OS_Time := GNAT.OS_Lib.Invalid_Time;
   begin
      if Metadata.Has_Modification_Time
        and then Filetime_To_OS_Time (Metadata.Modification_Time, OS_Time)
      then
         GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp (Path, OS_Time);
      end if;

      if Metadata.Has_Windows_Attributes
        and then (Metadata.Windows_Attributes and 16#0000_0001#) /= 0
      then
         GNAT.OS_Lib.Set_Read_Only (Path);
      end if;
   end Apply_Metadata;

end Zlib.Seven_Zip_Properties;
