package body Zlib.Stream_Bits is

   function Length
     (Source : Bit_Source)
      return Natural
   is
   begin
      if Source.Last < Source.First then
         return 0;
      end if;

      return Source.Last - Source.First + 1;
   end Length;

   procedure Clear_Buffer
     (Source : in out Bit_Source)
   is
   begin
      Source.First := 1;
      Source.Last  := 0;
   end Clear_Buffer;

   procedure Compact
     (Source : in out Bit_Source)
   is
      Remaining : constant Natural := Length (Source);
   begin
      if Remaining = 0 then
         Clear_Buffer (Source);
         return;
      end if;

      if Source.First = 1 then
         return;
      end if;

      for I in 0 .. Remaining - 1 loop
         Source.Buffer (I + 1) := Source.Buffer (Source.First + I);
      end loop;

      Source.First := 1;
      Source.Last  := Remaining;
   end Compact;

   procedure Advance_Byte
     (Source : in out Bit_Source)
   is
   begin
      if Length (Source) = 0 then
         return;
      end if;

      Source.First := Source.First + 1;
      Source.Bit := 0;
      Source.Absolute_Consumed := Source.Absolute_Consumed + 1;

      --  Do not compact on every consumed byte. That caused avoidable
      --  O(n) copy churn in the streaming hot path. Compact only when the
      --  live window is empty or when a significant prefix has accumulated.
      if Length (Source) = 0 then
         Clear_Buffer (Source);
      elsif Source.First > Max_Buffered_Bytes / 2 then
         Compact (Source);
      end if;
   end Advance_Byte;

   procedure Reset
     (Source : in out Bit_Source)
   is
   begin
      Clear_Buffer (Source);
      Source.Bit := 0;
      Source.Absolute_Consumed := 0;
      Source.Absolute_Appended := 0;
      Source.Last_Append_First := 0;
      Source.Last_Append_Last := 0;
   end Reset;

   procedure Append
     (Source : in out Bit_Source;
      Data   : Ada.Streams.Stream_Element_Array)
   is
      Old_Length : constant Natural := Length (Source);
      New_Length : constant Natural := Old_Length + Data'Length;
      Pos        : Natural;
   begin
      if Data'Length = 0 then
         return;
      end if;

      if New_Length > Max_Buffered_Bytes then
         --  The streaming decoder must not buffer an unbounded body. Callers
         --  should append data incrementally as decoding consumes input.
         raise Program_Error with "Zlib.Stream_Bits buffer limit exceeded";
      end if;

      if Source.Last + Data'Length > Max_Buffered_Bytes then
         Compact (Source);
      end if;

      Pos := Source.Last + 1;
      for I in Data'Range loop
         Source.Buffer (Pos) := Data (I);
         Pos := Pos + 1;
      end loop;

      if Old_Length = 0 then
         Source.First := 1;
      end if;

      Source.Last := Source.Last + Data'Length;
      Source.Last_Append_First := Source.Absolute_Appended + 1;
      Source.Last_Append_Last := Source.Absolute_Appended + Data'Length;
      Source.Absolute_Appended := Source.Absolute_Appended + Data'Length;
   end Append;

   function Buffered_Bytes
     (Source : Bit_Source)
      return Natural
   is
   begin
      return Length (Source);
   end Buffered_Bytes;

   function Has_Bits
     (Source : Bit_Source;
      Count  : Natural)
      return Boolean
   is
      Available : Natural;
   begin
      if Count = 0 then
         return True;
      end if;

      if Length (Source) = 0 then
         return False;
      end if;

      Available := Length (Source) * 8 - Source.Bit;
      return Available >= Count;
   end Has_Bits;

   function Read_Bit
     (Source : in out Bit_Source;
      Status : out Read_Status)
      return Boolean
   is
      Value : Boolean;
      Byte  : Ada.Streams.Stream_Element;
   begin
      if Length (Source) = 0 then
         Status := Need_Input;
         return False;
      end if;

      Byte := Source.Buffer (Source.First);
      Value := (Natural (Byte) / (2 ** Source.Bit)) mod 2 = 1;

      if Source.Bit = 7 then
         Advance_Byte (Source);
      else
         Source.Bit := Source.Bit + 1;
      end if;

      Status := Ok;
      return Value;
   end Read_Bit;

   function Can_Represent_Bit_Count
     (Count : Natural)
      return Boolean
     with SPARK_Mode => On
   is
      Max_Value : Natural := 0;
   begin
      for I in 1 .. Count loop
         pragma Unreferenced (I);

         if Max_Value > (Natural'Last - 1) / 2 then
            return False;
         end if;

         Max_Value := Max_Value * 2 + 1;
      end loop;

      return True;
   end Can_Represent_Bit_Count;

   function Read_Bits
     (Source : in out Bit_Source;
      Count  : Natural;
      Status : out Read_Status)
      return Natural
   is
      Result : Natural := 0;
      Place  : Natural := 1;
   begin
      if not Can_Represent_Bit_Count (Count) then
         Status := Invalid_State;
         return 0;
      end if;

      if not Has_Bits (Source, Count) then
         Status := Need_Input;
         return 0;
      end if;

      if Count = 0 then
         Status := Ok;
         return 0;
      end if;

      for I in 0 .. Count - 1 loop
         declare
            Bit_Status : Read_Status;
            Bit_Value  : constant Boolean := Read_Bit (Source, Bit_Status);
         begin
            if Bit_Status /= Ok then
               Status := Invalid_State;
               return 0;
            end if;

            if Bit_Value then
               Result := Result + Place;
            end if;

            if I < Count - 1 then
               Place := Place * 2;
            end if;
         end;
      end loop;

      Status := Ok;
      return Result;
   end Read_Bits;

   procedure Align_To_Byte
     (Source : in out Bit_Source)
   is
   begin
      if Source.Bit /= 0 and then Length (Source) > 0 then
         Advance_Byte (Source);
      else
         Source.Bit := 0;
      end if;
   end Align_To_Byte;

   function Read_Byte_Aligned
     (Source : in out Bit_Source;
      Status : out Read_Status)
      return Ada.Streams.Stream_Element
   is
      Result : Ada.Streams.Stream_Element := 0;
   begin
      if Source.Bit /= 0 then
         Status := Invalid_State;
         return 0;
      end if;

      if Length (Source) = 0 then
         Status := Need_Input;
         return 0;
      end if;

      Result := Source.Buffer (Source.First);
      Advance_Byte (Source);
      Status := Ok;
      return Result;
   end Read_Byte_Aligned;

   function Peek_Byte_Aligned
     (Source : Bit_Source;
      Offset : Natural;
      Status : out Read_Status)
      return Ada.Streams.Stream_Element
   is
      Index : constant Natural := Source.First + Offset;
   begin
      if Source.Bit /= 0 then
         Status := Invalid_State;
         return 0;
      end if;

      if Offset >= Length (Source) then
         Status := Need_Input;
         return 0;
      end if;

      Status := Ok;
      return Source.Buffer (Index);
   end Peek_Byte_Aligned;

   function Input_Consumed
     (Source : Bit_Source)
      return Natural
   is
   begin
      if Source.Last_Append_First = 0
        or else Source.Absolute_Consumed < Source.Last_Append_First
      then
         return 0;
      end if;

      if Source.Absolute_Consumed >= Source.Last_Append_Last then
         return Source.Last_Append_Last - Source.Last_Append_First + 1;
      end if;

      return Source.Absolute_Consumed - Source.Last_Append_First + 1;
   end Input_Consumed;

end Zlib.Stream_Bits;
