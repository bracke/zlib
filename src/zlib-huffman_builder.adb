package body Zlib.Huffman_Builder is

   function Ceil_Log2
     (Value : Positive)
      return Natural
     with SPARK_Mode => On
   is
      Power  : Natural := 1;
      Result : Natural := 0;
   begin
      while Power < Value and then Result < Max_Deflate_Code_Length + 1 loop
         pragma Loop_Invariant (Result <= Max_Deflate_Code_Length + 1);
         pragma Loop_Invariant (Power <= 2 ** Result);
         pragma Loop_Variant (Increases => Result);
         Power := Power * 2;
         Result := Result + 1;
      end loop;

      return Natural'Max (Result, 1);
   end Ceil_Log2;

   procedure Build_Lengths
     (Frequencies     : Frequency_Array;
      Lengths         : out Length_Array;
      Required_Symbol : Natural)
   is
      Present_Count : Natural := 0;
      Base_Length   : Natural;
      Short_Count   : Natural;
      Long_Count    : Natural;
      Assigned      : Natural := 0;
   begin
      pragma Assert
        (Frequencies'First = Lengths'First and then Frequencies'Last = Lengths'Last,
         "Huffman_Builder.Build_Lengths requires matching frequency/length ranges");
      pragma Assert
        (Required_Symbol in Frequencies'Range,
         "Huffman_Builder.Build_Lengths required symbol outside frequency range");

      Lengths := [others => 0];

      for Symbol in Frequencies'Range loop
         if Frequencies (Symbol) /= 0 or else Symbol = Required_Symbol then
            Present_Count := Present_Count + 1;
         end if;
      end loop;

      if Present_Count = 1 and then Frequencies'Length > 1 then
         Present_Count := 2;
      end if;

      Base_Length := Ceil_Log2 (Positive (Present_Count));

      declare
         Full_Leaves : constant Natural := 2 ** Base_Length;
         Deficit     : constant Natural := Full_Leaves - Present_Count;
      begin
         Short_Count := Deficit;
         Long_Count  := Present_Count - Short_Count;
      end;

      for Symbol in Frequencies'Range loop
         if Frequencies (Symbol) /= 0 or else Symbol = Required_Symbol then
            Assigned := Assigned + 1;
            if Assigned <= Short_Count and then Base_Length > 1 then
               Lengths (Symbol) := Base_Length - 1;
            else
               Lengths (Symbol) := Base_Length;
            end if;
         end if;
      end loop;

      if Assigned = 1 then
         for Symbol in Lengths'Range loop
            if Symbol /= Required_Symbol then
               Assigned := Assigned + 1;
               if Assigned <= Short_Count and then Base_Length > 1 then
                  Lengths (Symbol) := Base_Length - 1;
               else
                  Lengths (Symbol) := Base_Length;
               end if;
               exit;
            end if;
         end loop;
      end if;

      pragma Assert (Long_Count > 0, "Huffman_Builder must leave at least one long code");
      pragma Assert (Base_Length <= Max_Deflate_Code_Length, "Huffman length exceeds Deflate maximum");
   end Build_Lengths;

end Zlib.Huffman_Builder;
