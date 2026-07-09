with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Zlib; use Zlib;
with Zlib_Bench_Support;

procedure Zlib_Bench_Matrix is
   package CLI renames Ada.Command_Line;
   package TIO renames Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use type Zlib.Byte_Array;
   use Zlib_Bench_Support;

   Size         : Natural := 1_048_576;
   Repeat_Count : Positive := 3;
   Input_Chunk  : Positive := 32_768;
   Output_Chunk : Positive := 32_768;
   Verify       : Boolean := True;
   Status       : Zlib.Status_Code;

   Patterns : constant array (Positive range 1 .. 3) of Pattern_Kind :=
     [Pattern_Randomish, Pattern_Repeated, Pattern_Text_Like];
   Wrappers : constant array (Positive range 1 .. 3) of Wrapper_Kind :=
     [Wrapper_Zlib, Wrapper_Gzip, Wrapper_Raw];
   Levels   : constant array (Positive range 1 .. 4) of Zlib.Compression_Level :=
     [0, 1, 6, 9];

   procedure Usage is
   begin
      TIO.Put_Line ("usage: zlib_bench_matrix [--size BYTES] [--repeat N]");
      TIO.Put_Line ("       [--input-chunk BYTES] [--output-chunk BYTES] [--no-verify]");
      TIO.Put_Line ("       all value options also accept --name=value form");
   end Usage;

   function Pattern_Image (Pattern : Pattern_Kind) return String is
   begin
      case Pattern is
         when Pattern_Randomish => return "random-ish";
         when Pattern_Repeated  => return "repeated";
         when Pattern_Text_Like => return "text-like";
      end case;
   end Pattern_Image;

   function Clean_Image (Value : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
   end Clean_Image;

   function Percent_Saved
     (Compressed_Bytes : Natural;
      Input_Bytes      : Natural)
      return Long_Float
   is
   begin
      if Input_Bytes = 0 then
         return 0.0;
      end if;

      return
        (1.0 - Long_Float (Compressed_Bytes) / Long_Float (Input_Bytes)) *
        100.0;
   end Percent_Saved;

   function Need_Value
     (Index : in out Natural;
      Name  : String;
      Value : out Unbounded_String)
      return Boolean
   is
   begin
      if Index >= CLI.Argument_Count then
         TIO.Put_Line ("usage error: missing value for " & Name);
         Value := Null_Unbounded_String;
         return False;
      end if;

      Index := Index + 1;
      Value := To_Unbounded_String (CLI.Argument (Index));
      return True;
   end Need_Value;

   procedure Run_Case
     (Pattern : Pattern_Kind;
      Wrapper : Wrapper_Kind;
      Level   : Zlib.Compression_Level)
   is
      Input            : constant Zlib.Byte_Array := Synthetic_Data (Pattern, Size);
      Config           : constant Compression_Config :=
        (Wrapper      => Wrapper,
         Mode         => Zlib.Auto,
         Level        => Level,
         Use_Level    => True,
         Have_Mode    => False,
         Input_Chunk  => Input_Chunk,
         Output_Chunk => Output_Chunk,
         Repeat_Count => Repeat_Count,
         Verify       => Verify);
      Last_Output_Len  : Natural := 0;
      Min_Output_Len   : Natural := Natural'Last;
      Max_Output_Len   : Natural := 0;
      Total_Input      : Natural := 0;
      Total_Compressed : Natural := 0;
      Verified         : Boolean := True;
      Start_Time       : Ada.Calendar.Time;
      Stop_Time        : Ada.Calendar.Time;
   begin
      Start_Time := Ada.Calendar.Clock;
      for Iteration in 1 .. Repeat_Count loop
         declare
            Encoded : constant Zlib.Byte_Array := Streaming_Compress (Input, Config, Status);
         begin
            if Status /= Zlib.Ok then
               TIO.Put_Line
                 (Pattern_Image (Pattern) & "," & Wrapper_Image (Wrapper) & "," &
                  Clean_Image (Zlib.Compression_Level'Image (Level)) & ",compress-error," &
                  Zlib.Status_Image (Status));
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            if Verify then
               declare
                  Inflate_Config : Zlib_Bench_Support.Inflate_Config :=
                    (Wrapper      => Wrapper,
                     Input_Chunk  => Input_Chunk,
                     Output_Chunk => Output_Chunk,
                     Repeat_Count => 1,
                     Expect_Size  => 0,
                     Have_Expect  => False);
                  Decoded : constant Zlib.Byte_Array :=
                    Streaming_Inflate (Encoded, Inflate_Config, Status);
               begin
                  if Status /= Zlib.Ok or else Decoded /= Input then
                     Verified := False;
                  end if;
               end;
            end if;

            Last_Output_Len := Encoded'Length;
            Min_Output_Len := Natural'Min (Min_Output_Len, Encoded'Length);
            Max_Output_Len := Natural'Max (Max_Output_Len, Encoded'Length);
            Total_Input := Total_Input + Input'Length;
            Total_Compressed := Total_Compressed + Encoded'Length;
         end;
      end loop;
      Stop_Time := Ada.Calendar.Clock;

      TIO.Put_Line
        (Pattern_Image (Pattern) & "," &
         Wrapper_Image (Wrapper) & "," &
         Clean_Image (Zlib.Compression_Level'Image (Level)) & "," &
         Clean_Image (Natural'Image (Input'Length)) & "," &
         Clean_Image (Natural'Image (Last_Output_Len)) & "," &
         Clean_Image (Long_Float'Image (Ratio (Last_Output_Len, Input'Length))) & "," &
         Clean_Image (Long_Float'Image (Ratio (Total_Compressed, Total_Input))) & "," &
         Clean_Image (Natural'Image (Min_Output_Len)) & "," &
         Clean_Image (Natural'Image (Max_Output_Len)) & "," &
         Clean_Image (Long_Float'Image (Long_Float (Total_Compressed) / Long_Float (Repeat_Count))) & "," &
         Clean_Image (Long_Float'Image (Percent_Saved (Last_Output_Len, Input'Length))) & "," &
         Clean_Image (Positive'Image (Repeat_Count)) & "," &
         Clean_Image (Duration'Image (Stop_Time - Start_Time)) & "," &
         Clean_Image (Long_Float'Image (Throughput_MiB_S (Total_Input, Stop_Time - Start_Time))) & "," &
         (if Verify then (if Verified then "yes" else "no") else "disabled"));

      if Verify and then not Verified then
         CLI.Set_Exit_Status (CLI.Failure);
      end if;
   end Run_Case;

begin
   declare
      I : Natural := 1;
   begin
      while I <= CLI.Argument_Count loop
         declare
            Arg   : constant String := CLI.Argument (I);
            Ok    : Boolean;
            Value : Unbounded_String;
         begin
            if Starts_With (Arg, "--size=") then
               Size := Parse_Natural (Option_Value (Arg, "--size="), Ok);
            elsif Arg = "--size" then
               if not Need_Value (I, "--size", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Size := Parse_Natural (To_String (Value), Ok);
            elsif Starts_With (Arg, "--repeat=") then
               Repeat_Count := Parse_Positive (Option_Value (Arg, "--repeat="), Ok);
            elsif Arg = "--repeat" then
               if not Need_Value (I, "--repeat", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Repeat_Count := Parse_Positive (To_String (Value), Ok);
            elsif Starts_With (Arg, "--input-chunk=") then
               Input_Chunk := Parse_Positive (Option_Value (Arg, "--input-chunk="), Ok);
            elsif Arg = "--input-chunk" then
               if not Need_Value (I, "--input-chunk", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Input_Chunk := Parse_Positive (To_String (Value), Ok);
            elsif Starts_With (Arg, "--output-chunk=") then
               Output_Chunk := Parse_Positive (Option_Value (Arg, "--output-chunk="), Ok);
            elsif Arg = "--output-chunk" then
               if not Need_Value (I, "--output-chunk", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Output_Chunk := Parse_Positive (To_String (Value), Ok);
            elsif Arg = "--no-verify" then
               Verify := False;
               Ok := True;
            elsif Arg = "--help" then
               Usage;
               return;
            else
               Usage;
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            if not Ok then
               Usage;
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            I := I + 1;
         end;
      end loop;
   end;

   TIO.Put_Line
     ("pattern,wrapper,level,input_bytes,compressed_bytes,ratio,avg_ratio,min_bytes,max_bytes,avg_bytes," &
      "saved_pct,repeat,elapsed,throughput,verified");

   for Pattern of Patterns loop
      for Wrapper of Wrappers loop
         for Level of Levels loop
            Run_Case (Pattern, Wrapper, Level);
         end loop;
      end loop;
   end loop;
end Zlib_Bench_Matrix;
