module Main where

import Control.Monad
import System.IO
import System.Exit
import System.Console.GetOpt
import System.Environment
import System.FilePath
import Tail2Futhark.TAIL.Parser (parseFile)
import Tail2Futhark.TAIL.AST (Program)
import Tail2Futhark.Futhark.Pretty (pretty)
import Tail2Futhark.Compile (compile)
import Options

main :: IO ()
main = do
  cmdargs <- getArgs
  let (opts,args,errors) = runArgs cmdargs
  checkErrors errors
  program <- run (library opts) args
  let comp = (\f -> prelude ++ pretty f) . compile opts
  case outputFile opts of
    Nothing -> putStrLn . comp $ program
    Just  f -> withFile f WriteMode (\h -> hPutStr h $ comp $ program)


checkErrors :: [String] -> IO ()
checkErrors [] = return ()
checkErrors errors = hPutStrLn stderr (concat errors ++ usageInfo "Usage: tail2futhark [options] FILE" options) >> exitFailure

-- nonargs list of functions typed : Options -> Options
runArgs :: [String] -> (Options,[String],[String])
runArgs cmdargs = (opts,args,errors)
  where
  (nonargs,args,errors) = getOpt Permute options cmdargs
  opts = foldl (.) id nonargs defaultOptions -- MAGIC!!!! - our ooption record

run :: Bool -> [String] -> IO [(String,Program)]
run True fs = forM fs $ \f -> do
  prog <- withFile f ReadMode (flip parseFile f)
  return (dropExtension $ takeFileName f, prog)
run False [f] = do
  prog <- withFile f ReadMode $ flip parseFile f
  return [("main", prog)]
run False _ = do hPutStrLn stderr (usageInfo "Usage: tail2futhark [options] FILE" options)
                 exitFailure

prelude :: String
prelude = unlines [
   "-------------------------------------------------------------------",
   "-- This Futhark program is generated automatically by tail2futhark.",
   "-------------------------------------------------------------------",
   "",
   "fun radix_sort_up(xs: [n]u32) : ([n]u32,[n]i32) =",
   "  let is = iota(n) in",
   "  let is = map (+1) is in",
   "  loop (p:([n]u32,[n]i32) = (xs,is)) = for i < 32 do",
   "    radix_sort_step_up(p,i)",
   "  in p",
   "",
   "fun radix_sort_down(xs: [n]u32) : ([n]u32,[n]i32) =",
   "  let is = iota(n) in",
   "  let is = map (+1) is in",
   "  loop (p:([n]u32,[n]i32) = (xs,is)) = for i < 32 do",
   "    radix_sort_step_down(p,i)",
   "  in p",
   "",
   "fun radix_sort_step_up(p:([n]u32,[n]i32), digit_n:i32) : ([n]u32,[n]i32) =",
   "  let (xs,is)    = p",
   "  let bits       = map (fn (x:u32):i32 => i32((x >> u32(digit_n)) & 1u32)) xs",
   "  let bits_inv   = map (fn (b:i32):i32 => 1 - b) bits",
   "  let ps0        = scan (+) 0 bits_inv",
   "  let ps0_clean  = zipWith (*) bits_inv ps0",
   "  let ps1        = scan (+) 0 bits",
   "  let ps0_offset = reduce (+) 0 bits_inv",
   "  let ps1_clean  = map (fn (i:i32) : i32 => i+ps0_offset) ps1",
   "  let ps1_clean' = zipWith (*) bits ps1_clean",
   "  let ps         = zipWith (+) ps0_clean ps1_clean'",
   "  let ps_actual  = map (fn (p:i32) : i32 => p - 1) ps",
   "  in (write ps_actual xs (copy(xs)),",
   "      write ps_actual is (copy(is)))",
   "",
   "fun radix_sort_step_down(p:([n]u32,[n]i32), digit_n:i32) : ([n]u32,[n]i32) =",
   "  let (xs,is)    = p",
   "  let bits       = map (fn (x:u32):i32 => i32((x >> u32(digit_n)) & 1u32)) xs",
   "  let bits_inv   = map (fn (b:i32):i32 => 1 - b) bits",
   "  let ps1        = scan (+) 0 bits",
   "  let ps1_offset = reduce (+) 0 bits",
   "  let ps1_clean  = zipWith (*) bits ps1",
   "  let ps0        = scan (+) 0 bits_inv",
   "  let ps0_clean  = map (fn (i:i32) : i32 => i+ps1_offset) ps0",
   "  let ps0_clean' = zipWith (*) bits_inv ps0_clean",
   "  let ps         = zipWith (+) ps1_clean ps0_clean'",
   "  let ps_actual  = map (fn (p:i32) : i32 => p - 1) ps",
   "  in (write ps_actual xs (copy(xs)),",
   "      write ps_actual is (copy(is)))",
   "",
   "fun grade_up (xs: [n]i32) : [n]i32 =",
   "  let xs = map u32 xs in",
   "  let (_,is) = radix_sort_up xs in is",
   "",
   "fun grade_down (xs: [n]i32) : [n]i32 =",
   "  let xs = map u32 xs in",
   "  let (_,is) = radix_sort_down xs in is",
   "",
   "fun sgmScanSum (vals:[n]i32) (flags:[n]bool) : [n]i32 =",
   "  let pairs = scan ( fn ((v1,f1):(i32,bool)) ((v2,f2):(i32,bool)) : (i32,bool) =>",
   "                       let f = f1 || f2",
   "                       let v = if f2 then v2 else v1+v2",
   "                       in (v,f) ) (0,false) (zip vals flags)",
   "  let (res,_) = unzip pairs",
   "  in res",
   "",
   "fun replIdx (reps:[n]i32) : []i32 =",
   "  let tmp = scan (+) 0 reps",
   "  let sers = map (fn (i:i32):i32 => if i == 0 then 0 else unsafe tmp[i-1]) (iota(n))",
   "  let m = unsafe tmp[n-1]",
   "  let tmp2 = write sers (iota(n)) (replicate m 0)",
   "  let flags = map (>0) tmp2",
   "  let res = sgmScanSum tmp2 flags",
   "  in res",
   ""
   ]
