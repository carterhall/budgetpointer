main :: () {
  input := "Hello world!";
  output := HTTP.percent_encode(input);
  recovered := HTTP.percent_decode(output);
  print("Output: %\n", output);
  print("Recovered: %\n", recovered);

  str := "C";
  print("%\n", str[0] - #char "A");
}

HTTP :: #import,file "module.jai";
#import "Basic";