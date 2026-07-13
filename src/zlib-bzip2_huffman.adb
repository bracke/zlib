package body Zlib.BZip2_Huffman is

   use type Interfaces.Integer_32;

   procedure Build
     (Lengths : Length_Array;
      Table   : out Decode_Table;
      Status  : out Status_Code)
   is
      Next_Perm : Natural := 0;
      Vector    : Interfaces.Integer_32 := 0;
   begin
      Table := (others => <>);
      Status := Invalid_Huffman_Code;

      if Lengths'Length = 0 or else Lengths'Length > Max_Alphabet then
         return;
      end if;

      Table.Alpha_Size := Lengths'Length;
      Table.Min_Length := Max_Code_Length;
      Table.Max_Length := 1;

      for Length of Lengths loop
         if Length < 1 or else Length > Max_Code_Length then
            return;
         end if;
         Table.Min_Length := Natural'Min (Table.Min_Length, Length);
         Table.Max_Length := Natural'Max (Table.Max_Length, Length);
      end loop;

      --  Symbols in canonical order: by code length, then by symbol.
      for Length in Table.Min_Length .. Table.Max_Length loop
         for Symbol in Lengths'Range loop
            if Lengths (Symbol) = Length then
               Table.Perm (Next_Perm) := Symbol - Lengths'First;
               Next_Perm := Next_Perm + 1;
            end if;
         end loop;
      end loop;

      --  Base holds the running count of symbols shorter than each length.
      for Length of Lengths loop
         Table.Base (Length + 1) := Table.Base (Length + 1) + 1;
      end loop;
      for Index in 1 .. Max_Code_Length + 1 loop
         Table.Base (Index) := Table.Base (Index) + Table.Base (Index - 1);
      end loop;

      --  Limit holds the largest code of each length; a value above it needs
      --  another bit.
      for Length in Table.Min_Length .. Table.Max_Length loop
         Vector :=
           Vector + (Table.Base (Length + 1) - Table.Base (Length));
         Table.Limit (Length) := Vector - 1;
         Vector := Vector * 2;
      end loop;

      for Length in Table.Min_Length + 1 .. Table.Max_Length loop
         Table.Base (Length) :=
           ((Table.Limit (Length - 1) + 1) * 2) - Table.Base (Length);
      end loop;

      Status := Ok;
   end Build;

   function Decode
     (R      : in out Zlib.BZip2_Bits.Reader;
      Data   : Byte_Array;
      Table  : Decode_Table;
      Status : out Status_Code) return Natural
   is
      Length : Natural := Table.Min_Length;
      Value  : Interfaces.Integer_32;
      Raw    : Interfaces.Unsigned_32;
      Bit    : Boolean;
      Offset : Interfaces.Integer_32;
   begin
      Raw := Zlib.BZip2_Bits.Read_Bits (R, Data, Length, Status);
      if Status /= Ok then
         return 0;
      end if;
      Value := Interfaces.Integer_32 (Raw);

      while Value > Table.Limit (Length) loop
         Length := Length + 1;
         if Length > Table.Max_Length then
            Status := Invalid_Huffman_Code;
            return 0;
         end if;

         Bit := Zlib.BZip2_Bits.Read_Bit (R, Data, Status);
         if Status /= Ok then
            return 0;
         end if;

         Value := Value * 2;
         if Bit then
            Value := Value + 1;
         end if;
      end loop;

      Offset := Value - Table.Base (Length);
      if Offset < 0
        or else Offset > Interfaces.Integer_32 (Table.Alpha_Size - 1)
      then
         Status := Invalid_Huffman_Code;
         return 0;
      end if;

      Status := Ok;
      return Table.Perm (Natural (Offset));
   end Decode;

end Zlib.BZip2_Huffman;
