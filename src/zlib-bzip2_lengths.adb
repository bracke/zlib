package body Zlib.BZip2_Lengths is

   use type Interfaces.Unsigned_32;

   --  A node's weight carries its subtree depth in the low 8 bits and its
   --  frequency above them, so that comparing weights prefers the shallower of
   --  two equally likely subtrees. This is what keeps code lengths short enough
   --  to hit the cap on the first attempt for all but pathological inputs.
   Depth_Mask  : constant Natural := 16#FF#;
   Weight_Step : constant Natural := 2 ** 8;

   function Add_Weights (Left : Natural; Right : Natural) return Natural;

   function Add_Weights (Left : Natural; Right : Natural) return Natural is
      Frequency : constant Natural :=
        (Left / Weight_Step + Right / Weight_Step) * Weight_Step;
      Depth     : constant Natural :=
        1 + Natural'Max (Left mod Weight_Step, Right mod Weight_Step);
   begin
      --  Frequency is a multiple of Weight_Step and Depth stays below it, so a
      --  sum packs them exactly as the bitwise original does.
      return Frequency + Natural'Min (Depth, Depth_Mask);
   end Add_Weights;

   procedure Make_Code_Lengths
     (Frequencies : Frequency_Array;
      Lengths     : out Length_Array;
      Max_Length  : Natural := Encode_Max_Length)
   is
      Alpha_Size : constant Natural := Frequencies'Length;

      --  One-based, with a sentinel at 0, matching the shape of the original.
      Heap   : array (0 .. Alpha_Size + 1) of Natural := [others => 0];
      Weight : array (0 .. 2 * Alpha_Size + 1) of Natural := [others => 0];
      Parent : array (0 .. 2 * Alpha_Size + 1) of Integer := [others => -1];

      Heap_Size  : Natural;
      Node_Count : Natural;
      Too_Long   : Boolean;

      procedure Up_Heap (Start : Positive);
      procedure Down_Heap (Start : Positive);

      procedure Up_Heap (Start : Positive) is
         Position : Natural := Start;
         Item     : constant Natural := Heap (Start);
      begin
         while Weight (Item) < Weight (Heap (Position / 2)) loop
            Heap (Position) := Heap (Position / 2);
            Position := Position / 2;
         end loop;
         Heap (Position) := Item;
      end Up_Heap;

      procedure Down_Heap (Start : Positive) is
         Position : Natural := Start;
         Child    : Natural;
         Item     : constant Natural := Heap (Start);
      begin
         loop
            Child := Position * 2;
            exit when Child > Heap_Size;

            if Child < Heap_Size
              and then Weight (Heap (Child + 1)) < Weight (Heap (Child))
            then
               Child := Child + 1;
            end if;

            exit when Weight (Item) < Weight (Heap (Child));

            Heap (Position) := Heap (Child);
            Position := Child;
         end loop;
         Heap (Position) := Item;
      end Down_Heap;

      Left  : Natural;
      Right : Natural;
      Depth : Natural;
      Node  : Natural;
   begin
      Lengths := [others => 0];

      for Index in 1 .. Alpha_Size loop
         Weight (Index) :=
           (if Frequencies (Frequencies'First + Index - 1) = 0
            then 1
            else Frequencies (Frequencies'First + Index - 1)) * Weight_Step;
      end loop;

      loop
         Node_Count := Alpha_Size;
         Heap_Size := 0;

         Heap (0) := 0;
         Weight (0) := 0;
         Parent (0) := -2;

         for Index in 1 .. Alpha_Size loop
            Parent (Index) := -1;
            Heap_Size := Heap_Size + 1;
            Heap (Heap_Size) := Index;
            Up_Heap (Heap_Size);
         end loop;

         while Heap_Size > 1 loop
            Left := Heap (1);
            Heap (1) := Heap (Heap_Size);
            Heap_Size := Heap_Size - 1;
            Down_Heap (1);

            Right := Heap (1);
            Heap (1) := Heap (Heap_Size);
            Heap_Size := Heap_Size - 1;
            Down_Heap (1);

            Node_Count := Node_Count + 1;
            Parent (Left) := Node_Count;
            Parent (Right) := Node_Count;
            Weight (Node_Count) :=
              Add_Weights (Weight (Left), Weight (Right));
            Parent (Node_Count) := -1;

            Heap_Size := Heap_Size + 1;
            Heap (Heap_Size) := Node_Count;
            Up_Heap (Heap_Size);
         end loop;

         Too_Long := False;
         for Index in 1 .. Alpha_Size loop
            Depth := 0;
            Node := Index;
            while Parent (Node) >= 0 loop
               Node := Parent (Node);
               Depth := Depth + 1;
            end loop;

            Lengths (Lengths'First + Index - 1) := Depth;
            if Depth > Max_Length then
               Too_Long := True;
            end if;
         end loop;

         exit when not Too_Long;

         --  Halve every frequency and rebuild; the tree gets shallower.
         for Index in 1 .. Alpha_Size loop
            Weight (Index) :=
              (1 + (Weight (Index) / Weight_Step) / 2) * Weight_Step;
         end loop;
      end loop;
   end Make_Code_Lengths;

   procedure Assign_Codes
     (Lengths : Length_Array;
      Codes   : out Code_Array)
   is
      Value      : Interfaces.Unsigned_32 := 0;
      Min_Length : Natural := Natural'Last;
      Max_Length : Natural := 0;
   begin
      Codes := [others => 0];

      for Length of Lengths loop
         Min_Length := Natural'Min (Min_Length, Length);
         Max_Length := Natural'Max (Max_Length, Length);
      end loop;

      for Length in Min_Length .. Max_Length loop
         for Index in Lengths'Range loop
            if Lengths (Index) = Length then
               Codes (Codes'First + (Index - Lengths'First)) := Value;
               Value := Value + 1;
            end if;
         end loop;
         Value := Interfaces.Shift_Left (Value, 1);
      end loop;
   end Assign_Codes;

end Zlib.BZip2_Lengths;
