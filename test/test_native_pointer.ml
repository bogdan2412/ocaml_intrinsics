open Base
open Stdio
module NP = Ocaml_intrinsics.Native_pointer

module Ext_pointer_to_untagged_int : sig
  type t

  val create : int -> t
  val read : t -> int
  val write : t -> int -> unit
end = struct
  type t = int (* representation of external pointers using ocaml int *)

  external create : int -> t = "external_untagged_int_ref"

  let read t =
    let d = NP.ext_pointer_as_native_pointer t in
    NP.load_untagged_int d
  ;;

  let write t i =
    let d = NP.ext_pointer_as_native_pointer t in
    NP.store_untagged_int d i
  ;;
end

module Ext_pointer_to_float : sig
  type t (* representation of external pointers using ocaml int *)

  val create : float -> t
  val read : t -> float
  val write : t -> float -> unit
end = struct
  type t = int

  external create : float -> int = "external_unboxed_float_ref"

  let read t =
    let d = NP.ext_pointer_as_native_pointer t in
    NP.load_unboxed_float d
  ;;

  let write t f =
    let d = NP.ext_pointer_as_native_pointer t in
    NP.store_unboxed_float d f
  ;;
end

let test_int n =
  let ir = Ext_pointer_to_untagged_int.create n in
  let n' = Ext_pointer_to_untagged_int.read ir in
  printf "native_pointer int: read %d = %d\n" n n';
  let k = n + 1 in
  Ext_pointer_to_untagged_int.write ir k;
  let k' = Ext_pointer_to_untagged_int.read ir in
  printf "native_pointer int: read %d = %d\n" k k';
  n', k'
;;

let test_float n =
  let ir = Ext_pointer_to_float.create n in
  let n' = Ext_pointer_to_float.read ir in
  printf "native_pointer float: read %f = %f\n" n n';
  let k = n *. 13.0 in
  Ext_pointer_to_float.write ir k;
  let k' = Ext_pointer_to_float.read ir in
  printf "native_pointer float: read %f = %f\n" k k';
  n', k'
;;

let%expect_test "native_pointer int" =
  let numbers = [ 17 ] in
  List.iter ~f:(fun n -> ignore (test_int n : int * int)) numbers;
  [%expect
    {|
    native_pointer int: read 17 = 17
    native_pointer int: read 18 = 18
    |}]
;;

let%expect_test "native_pointer float" =
  let numbers = [ 42.0 ] in
  List.iter ~f:(fun n -> (test_float n : float * float) |> ignore) numbers;
  [%expect
    {|
    native_pointer float: read 42.000000 = 42.000000
    native_pointer float: read 546.000000 = 546.000000
    |}]
;;

let test_immediate_int n =
  let open NP in
  let raw = Expert.to_nativeint (unsafe_of_value n) in
  let n' : int = unsafe_to_value (Expert.of_nativeint raw) in
  printf "read %nd from %d (=%d)\n" raw n n';
  let k = Nativeint.( + ) raw 2n in
  let k' : int = unsafe_to_value (Expert.of_nativeint k) in
  printf "incr %nd (=%d)\n" k k';
  n', k'
;;

let%expect_test "native_pointer immediate int" =
  let numbers = [ 17 ] in
  List.iter ~f:(fun n -> ignore (test_immediate_int n : int * int)) numbers;
  [%expect
    {|
    read 35 from 17 (=17)
    incr 37 (=18)
    |}]
;;

let%expect_test "native pointer none matches" =
  let open NP in
  let v = Sys.opaque_identity None in
  let pv = unsafe_of_value v in
  let pn = unsafe_of_value None in
  printf "%nu = %nu" (Expert.to_nativeint pv) (Expert.to_nativeint pn);
  Expect_test_helpers_base.require (pv = pn);
  [%expect {| 1 = 1 |}]
;;

let%expect_test "native pointer values match" =
  let open NP in
  let v = [ 3 ] in
  let v0 = v in
  let v1 = v in
  let pv0 = unsafe_of_value v0 in
  let pv1 = unsafe_of_value v1 in
  Expect_test_helpers_base.require (pv0 = pv1);
  [%expect {| |}]
;;

let%expect_test "native pointer values differ" =
  let open NP in
  let v0 = [ 3 ] in
  let v1 = [ 4 ] in
  let pv0 = unsafe_of_value v0 in
  let pv1 = unsafe_of_value v1 in
  Expect_test_helpers_base.require (pv0 <> pv1);
  [%expect {| |}]
;;

let%expect_test "native pointer comparisons" =
  let open NP in
  let p0 = Expert.of_nativeint 0n in
  let p1 = advance p0 ~bytes:17n in
  Expect_test_helpers_base.require (p0 = p0);
  Expect_test_helpers_base.require (p0 <= p0);
  Expect_test_helpers_base.require (p0 >= p0);
  Expect_test_helpers_base.require (p0 <> p1);
  Expect_test_helpers_base.require (p0 < p1);
  Expect_test_helpers_base.require (p1 > p0);
  Expect_test_helpers_base.require_equal
    (module Nativeint)
    (difference_in_bytes p0 p1)
    17n;
  [%expect {| |}]
;;

let[@inline never] throw_away x = (Sys.opaque_identity x : _) |> ignore

let test_frametable (x : nativeint) =
  x
  |> NP.Expert.of_nativeint
  |> NP.unsafe_to_value
  |> fun x ->
  throw_away x;
  x
;;

let%expect_test "native_pointer frametable" =
  let numbers = [ 17n ] in
  List.iter ~f:(fun n -> printf "%d\n" (test_frametable n : int)) numbers;
  [%expect {| 8 |}]
;;

include Base_quickcheck.Export

module BI = struct
  include Base.Int

  type t = int [@@deriving quickcheck]
end

module BF = struct
  include Base.Float

  type t = float [@@deriving quickcheck]
end

module _ = struct
  let%test_unit "native_pointer int quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BI)
      ~f:(fun n ->
        let expect = n, n + 1 in
        let actual = test_int n in
        [%test_result: Int.t * Int.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  let%test_unit "native_pointer immediate int quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BI)
      ~f:(fun n ->
        let expect = n, n + 1 in
        let actual = test_immediate_int n in
        [%test_result: Int.t * Int.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  let%test_unit "native_pointer float quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BF)
      ~f:(fun n ->
        let expect = n, n *. 13.0 in
        let actual = test_float n in
        [%test_result: Float.t * Float.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  external create_immediate : int -> NP.t = "external_immediate_ref_as_native_pointer"

  let direct_test_immediate n =
    let ir = create_immediate n in
    let n' = NP.Int.unsafe_load_immediate ir in
    printf "native_pointer int: read %d = %d\n" n n';
    let k = n + 1 in
    NP.Int.store_immediate ir k;
    let k' = NP.Int.unsafe_load_immediate ir in
    printf "native_pointer int: read %d = %d\n" k k';
    n', k'
  ;;

  let%test_unit "native_pointer immediate quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BI)
      ~f:(fun n ->
        let expect = n, n + 1 in
        let actual = direct_test_immediate n in
        [%test_result: Int.t * Int.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  external create_untagged_int
    :  int
    -> NP.t
    = "external_untagged_int_ref_as_native_pointer"

  let direct_test_untagged_int n =
    let ir = create_untagged_int n in
    let n' = NP.load_untagged_int ir in
    printf "native_pointer int: read %d = %d\n" n n';
    let k = n + 1 in
    NP.store_untagged_int ir k;
    let k' = NP.load_untagged_int ir in
    printf "native_pointer int: read %d = %d\n" k k';
    n', k'
  ;;

  let%test_unit "native_pointer untagged int quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BI)
      ~f:(fun n ->
        let expect = n, n + 1 in
        let actual = direct_test_untagged_int n in
        [%test_result: Int.t * Int.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  external create_unboxed_float
    :  float
    -> NP.t
    = "external_unboxed_float_ref_as_native_pointer"

  let direct_test_unboxed_float n =
    let ir = create_unboxed_float n in
    let n' = NP.load_unboxed_float ir in
    printf "native_pointer float: read %f = %f\n" n n';
    let k = n *. 13.0 in
    NP.store_unboxed_float ir k;
    let k' = NP.load_unboxed_float ir in
    printf "native_pointer float: read %f = %f\n" k k';
    n', k'
  ;;

  let%test_unit "native_pointer unboxed float quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BF)
      ~f:(fun n ->
        let expect = n, n *. 13.0 in
        let actual = direct_test_unboxed_float n in
        [%test_result: Float.t * Float.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  external create_unboxed_int64
    :  int64
    -> NP.t
    = "external_unboxed_int64_ref_as_native_pointer"

  let direct_test_unboxed_int64 n =
    let ir = create_unboxed_int64 n in
    let n' = NP.load_unboxed_int64 ir in
    printf "native_pointer float: read %Ld = %Ld\n" n n';
    let k = Int64.(n + 7L) in
    NP.store_unboxed_int64 ir k;
    let k' = NP.load_unboxed_int64 ir in
    printf "native_pointer float: read %Ld = %Ld\n" k k';
    n', k'
  ;;

  module BInt64 = struct
    include Base.Int64

    type t = int64 [@@deriving quickcheck]
  end

  let%test_unit "native_pointer unboxed int64 quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BInt64)
      ~f:(fun n ->
        let expect = n, Int64.(n + 7L) in
        let actual = direct_test_unboxed_int64 n in
        [%test_result: Int64.t * Int64.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  external create_unboxed_int32
    :  int32
    -> NP.t
    = "external_unboxed_int32_ref_as_native_pointer"

  let direct_test_unboxed_int32 n =
    let ir = create_unboxed_int32 n in
    let n' = NP.load_unboxed_int32 ir in
    printf "native_pointer float: read %ld = %ld\n" n n';
    let k = Int32.(n + 7l) in
    NP.store_unboxed_int32 ir k;
    let k' = NP.load_unboxed_int32 ir in
    printf "native_pointer float: read %ld = %ld\n" k k';
    n', k'
  ;;

  module BInt32 = struct
    include Base.Int32

    type t = int32 [@@deriving quickcheck]
  end

  let%test_unit "native_pointer unboxed int32 quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BInt32)
      ~f:(fun n ->
        let expect = n, Int32.(n + 7l) in
        let actual = direct_test_unboxed_int32 n in
        [%test_result: Int32.t * Int32.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end

module _ = struct
  external create_unboxed_nativeint
    :  nativeint
    -> NP.t
    = "external_unboxed_nativeint_ref_as_native_pointer"

  let direct_test_unboxed_nativeint n =
    let ir = create_unboxed_nativeint n in
    let n' = NP.load_unboxed_nativeint ir in
    printf "native_pointer float: read %nd = %nd\n" n n';
    let k = Nativeint.(n + 7n) in
    NP.store_unboxed_nativeint ir k;
    let k' = NP.load_unboxed_nativeint ir in
    printf "native_pointer float: read %nd = %nd\n" k k';
    n', k'
  ;;

  module BNativeint = struct
    include Base.Nativeint

    type t = nativeint [@@deriving quickcheck]
  end

  let%test_unit "native_pointer unboxed nativeint quickcheck" =
    Base_quickcheck.Test.run_exn
      (module BNativeint)
      ~f:(fun n ->
        let expect = n, Nativeint.(n + 7n) in
        let actual = direct_test_unboxed_nativeint n in
        [%test_result: Nativeint.t * Nativeint.t] ~expect actual)
  ;;

  type t = int [@@deriving quickcheck]
end
