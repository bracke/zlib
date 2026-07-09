with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Zlib; use Zlib;
with Zlib_Bench_Support;

procedure Zlib_Bench_Gzip is
   package CLI renames Ada.Command_Line;
   package TIO renames Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use type Zlib.Byte_Array;
   use Zlib_Bench_Support;

   Config       : Compression_Config := (Wrapper => Wrapper_Gzip, others => <>);
   Input_Path   : Unbounded_String;
   Have_Input   : Boolean := False;
   Pattern      : Pattern_Kind := Pattern_Randomish;
   Size         : Natural := 1_048_576;
   Status       : Zlib.Status_Code;

   procedure Usage is
   begin
      TIO.Put_Line
        ("usage: zlib_bench_gzip [--input FILE | --pattern random-ish|repeated|text-like --size BYTES]");
      TIO.Put_Line
        ("       [--wrapper zlib|gzip|raw] [--mode stored|fixed|dynamic|auto | --level 0..9]");
      TIO.Put_Line
        ("       [--input-chunk BYTES] [--output-chunk BYTES] [--repeat N] [--no-verify]");
      TIO.Put_Line ("       all value options also accept --name=value form");
   end Usage;

   function Load_Input return Zlib.Byte_Array is
   begin
      if Have_Input then
         return Read_File (To_String (Input_Path), Status);
      else
         Status := Zlib.Ok;
         return Synthetic_Data (Pattern, Size);
      end if;
   end Load_Input;

   function Need_Value
     (Index : in out Natural;
      Name  : String;
      Value : out Unbounded_String)
      return Boolean
   is
   begin
      if Index >= CLI.Argument_Count then
         TIO.Put_Line ("usage error: missing value for " & Name);
         return False;
      end if;

      Index := Index + 1;
      Value := To_Unbounded_String (CLI.Argument (Index));
      return True;
   end Need_Value;

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
            if Starts_With (Arg, "--input=") then
               Input_Path := To_Unbounded_String (Option_Value (Arg, "--input="));
               Have_Input := True;
            elsif Arg = "--input" then
               if not Need_Value (I, "--input", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Input_Path := Value;
               Have_Input := True;
            elsif Starts_With (Arg, "--wrapper=") then
               Config.Wrapper := Parse_Wrapper (Option_Value (Arg, "--wrapper="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--wrapper" then
               if not Need_Value (I, "--wrapper", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Wrapper := Parse_Wrapper (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--mode=") then
               Config.Mode := Parse_Mode (Option_Value (Arg, "--mode="), Ok);
               Config.Have_Mode := Ok;
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--mode" then
               if not Need_Value (I, "--mode", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Mode := Parse_Mode (To_String (Value), Ok);
               Config.Have_Mode := Ok;
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--level=") then
               Config.Level := Parse_Level (Option_Value (Arg, "--level="), Ok);
               Config.Use_Level := Ok;
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--level" then
               if not Need_Value (I, "--level", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Level := Parse_Level (To_String (Value), Ok);
               Config.Use_Level := Ok;
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--input-chunk=") then
               Config.Input_Chunk := Parse_Positive (Option_Value (Arg, "--input-chunk="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--input-chunk" then
               if not Need_Value (I, "--input-chunk", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Input_Chunk := Parse_Positive (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--output-chunk=") then
               Config.Output_Chunk := Parse_Positive (Option_Value (Arg, "--output-chunk="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--output-chunk" then
               if not Need_Value (I, "--output-chunk", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Output_Chunk := Parse_Positive (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--repeat=") then
               Config.Repeat_Count := Parse_Positive (Option_Value (Arg, "--repeat="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--repeat" then
               if not Need_Value (I, "--repeat", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Repeat_Count := Parse_Positive (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--size=") then
               Size := Parse_Natural (Option_Value (Arg, "--size="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--size" then
               if not Need_Value (I, "--size", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Size := Parse_Natural (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--pattern=") then
               Pattern := Parse_Pattern (Option_Value (Arg, "--pattern="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--pattern" then
               if not Need_Value (I, "--pattern", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Pattern := Parse_Pattern (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--no-verify" then
               Config.Verify := False;
            elsif Arg = "--help" then
               Usage;
               return;
            else
               Usage;
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            I := I + 1;
         end;
      end loop;
   end;

   if Config.Have_Mode and then Config.Use_Level then
      TIO.Put_Line ("usage error: --mode and --level are mutually exclusive");
      CLI.Set_Exit_Status (CLI.Failure);
      return;
   end if;

   declare
      Input            : constant Zlib.Byte_Array := Load_Input;
      Last_Output_Len  : Natural := 0;
      Min_Output_Len   : Natural := Natural'Last;
      Max_Output_Len   : Natural := 0;
      Start_Time       : Ada.Calendar.Time;
      Stop_Time        : Ada.Calendar.Time;
      Total_In         : Natural := 0;
      Total_Compressed : Natural := 0;
      Verified         : Boolean := True;
   begin
      if Status /= Zlib.Ok then
         TIO.Put_Line ("input failed: " & Zlib.Status_Image (Status));
         CLI.Set_Exit_Status (CLI.Failure);
         return;
      end if;

      Start_Time := Ada.Calendar.Clock;
      for Iteration in 1 .. Config.Repeat_Count loop
         declare
            Encoded : constant Zlib.Byte_Array := Streaming_Compress (Input, Config, Status);
         begin
            if Status /= Zlib.Ok then
               TIO.Put_Line ("compress failed: " & Zlib.Status_Image (Status));
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            if Config.Verify then
               declare
                  Inflate_Config : Zlib_Bench_Support.Inflate_Config :=
                    (Wrapper      => Config.Wrapper,
                     Input_Chunk  => Config.Input_Chunk,
                     Output_Chunk => Config.Output_Chunk,
                     Repeat_Count => 1,
                     Expect_Size  => 0,
                     Have_Expect  => False);
                  Decoded : constant Zlib.Byte_Array := Streaming_Inflate
                    (Encoded, Inflate_Config, Status);
               begin
                  if Status /= Zlib.Ok or else Decoded /= Input then
                     Verified := False;
                     TIO.Put_Line ("verify failed: " & Zlib.Status_Image (Status));
                     CLI.Set_Exit_Status (CLI.Failure);
                     return;
                  end if;
               end;
            end if;

            Last_Output_Len := Encoded'Length;
            Min_Output_Len := Natural'Min (Min_Output_Len, Encoded'Length);
            Max_Output_Len := Natural'Max (Max_Output_Len, Encoded'Length);
            Total_In := Total_In + Input'Length;
            Total_Compressed := Total_Compressed + Encoded'Length;
         end;
      end loop;
      Stop_Time := Ada.Calendar.Clock;

      TIO.Put_Line ("wrapper: " & Wrapper_Image (Config.Wrapper));
      if Config.Use_Level then
         TIO.Put_Line ("level:" & Zlib.Compression_Level'Image (Config.Level));
      else
         TIO.Put_Line ("mode: " & Mode_Image (Config.Mode));
      end if;
      TIO.Put_Line ("input bytes:" & Natural'Image (Input'Length));
      TIO.Put_Line ("output bytes:" & Natural'Image (Last_Output_Len));
      TIO.Put_Line ("compressed bytes:" & Natural'Image (Last_Output_Len));
      TIO.Put_Line ("min compressed bytes:" & Natural'Image (Min_Output_Len));
      TIO.Put_Line ("max compressed bytes:" & Natural'Image (Max_Output_Len));
      TIO.Put_Line
        ("avg compressed bytes:" & Natural'Image (Total_Compressed / Config.Repeat_Count));
      TIO.Put_Line ("ratio:" & Long_Float'Image (Ratio (Last_Output_Len, Input'Length)) & "%");
      TIO.Put_Line ("avg ratio:" & Long_Float'Image (Ratio (Total_Compressed, Total_In)) & "%");
      TIO.Put_Line ("repeat:" & Positive'Image (Config.Repeat_Count));
      TIO.Put_Line ("elapsed:" & Duration'Image (Stop_Time - Start_Time) & " s");
      TIO.Put_Line ("avg elapsed:" & Duration'Image ((Stop_Time - Start_Time) / Config.Repeat_Count) & " s");
      TIO.Put_Line
        ("throughput:"
         & Long_Float'Image (Throughput_MiB_S (Total_In, Stop_Time - Start_Time))
         & " MiB/s");
      TIO.Put_Line ("input chunk:" & Positive'Image (Config.Input_Chunk));
      TIO.Put_Line ("output chunk:" & Positive'Image (Config.Output_Chunk));
      if Config.Verify then
         TIO.Put_Line ("verified: " & (if Verified then "yes" else "no"));
      else
         TIO.Put_Line ("verified: no (disabled)");
      end if;
      TIO.Put_Line ("total compressed bytes:" & Natural'Image (Total_Compressed));
   end;
end Zlib_Bench_Gzip;
