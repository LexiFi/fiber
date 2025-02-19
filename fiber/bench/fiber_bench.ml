open Stdune
open Fiber.O

let n = 1000

let%bench_fun "bind" =
 fun () ->
  Fiber.run
    ~iter:(fun () -> assert false)
    (let rec loop = function
       | 0 -> Fiber.return ()
       | n -> Fiber.return () >>= fun () -> loop (n - 1)
     in
     loop n)

let%bench_fun "create ivar and immediately read" =
 fun () ->
  let ivar = Fiber.Ivar.create () in
  Fiber.run ~iter:(fun () -> [ Fiber.Fill (ivar, ()) ]) (Fiber.Ivar.read ivar)

let%bench_fun "ivar" =
 fun () ->
  let ivar = ref (Fiber.Ivar.create ()) in
  Fiber.run
    ~iter:(fun () -> [ Fiber.Fill (!ivar, ()) ])
    (let rec loop = function
       | 0 -> Fiber.return ()
       | n ->
         ivar := Fiber.Ivar.create ();
         let* () = Fiber.Ivar.read !ivar in
         loop (n - 1)
     in
     loop n)

let%bench_fun "Var.set" =
  let var = Fiber.Var.create () in
  fun () ->
    Fiber.run
      ~iter:(fun () -> assert false)
      (let rec loop = function
         | 0 -> Fiber.return ()
         | n -> Fiber.Var.set var n (fun () -> loop (n - 1))
       in
       loop n)

let%bench_fun "Var.get" =
  let var = Fiber.Var.create () in
  fun () ->
    Fiber.run
      ~iter:(fun () -> assert false)
      (let rec loop = function
         | 0 -> Fiber.return ()
         | n ->
           let* (_ : int option) = Fiber.Var.get var in
           loop (n - 1)
       in
       Fiber.Var.set var 0 (fun () -> loop n))

let exns =
  List.init n ~f:(fun _ ->
      { Exn_with_backtrace.exn = Exit
      ; backtrace = Printexc.get_raw_backtrace ()
      })

let%bench "catching exceptions" =
  Fiber.run
    ~iter:(fun () -> assert false)
    (Fiber.map_reduce_errors
       (module Monoid.Unit)
       ~on_error:(fun _ -> Fiber.return ())
       (fun () -> Fiber.reraise_all exns))
  |> ignore

let%bench "installing handlers" =
  Fiber.run
    ~iter:(fun () -> assert false)
    (let rec loop = function
       | 0 -> Fiber.return ()
       | n ->
         let* (_ : (unit, unit) result) =
           Fiber.map_reduce_errors
             (module Monoid.Unit)
             ~on_error:(fun _ -> Fiber.return ())
             (fun () -> Fiber.return ())
         in
         loop (n - 1)
     in
     loop n)
  |> ignore

let%bench_fun "Fiber.fork_and_join" =
 fun () ->
  Fiber.run
    ~iter:(fun () -> assert false)
    (let rec loop = function
       | 0 -> Fiber.return ()
       | n ->
         let+ (), () =
           Fiber.fork_and_join Fiber.return (fun () -> loop (n - 1))
         in
         ()
     in
     loop 1000)

let%bench_fun "Fiber.fork_and_join_unit" =
 fun () ->
  Fiber.run
    ~iter:(fun () -> assert false)
    (let rec loop = function
       | 0 -> Fiber.return ()
       | n -> Fiber.fork_and_join_unit Fiber.return (fun () -> loop (n - 1))
     in
     loop 1000)

let%bench_fun "Fiber.parallel_iter" =
  let l = List.init 1000 ~f:Fun.id in
  fun () ->
    Fiber.run
      ~iter:(fun () -> assert false)
      (Fiber.parallel_iter l ~f:(fun _ -> Fiber.return ()))

let%bench_fun "Fiber.parallel_map" =
  let l = List.init 1000 ~f:Fun.id in
  fun () ->
    Fiber.run
      ~iter:(fun () -> assert false)
      (Fiber.parallel_map l ~f:Fiber.return)
    |> ignore

let pool_run tasks =
  Fiber.run
    ~iter:(fun () -> assert false)
    (let pool = Fiber.Pool.create () in
     Fiber.fork_and_join_unit
       (fun () -> Fiber.Pool.run pool)
       (fun () ->
         let* () =
           Fiber.parallel_iter tasks ~f:(fun (_ : int) ->
               Fiber.Pool.task pool ~f:Fiber.return)
         in
         Fiber.Pool.close pool))
  |> ignore

(* some pools are used to run many fibers *)
let%bench_fun "Fiber.Pool.run - big" =
  let l = List.init 1000 ~f:Fun.id in
  fun () -> pool_run l

(* other pools are one-off transients that are created and discarded *)
let%bench_fun "Fiber.Pool.run - small" =
  let l = List.init 2 ~f:Fun.id in
  fun () -> pool_run l

module M = Fiber.Make_parallel_map (Int.Map)

let map =
  List.init 1000 ~f:Fun.id
  |> List.map ~f:(fun i -> (i, i))
  |> Int.Map.of_list_exn

let%bench "Fiber.parallel_iter_seq" =
  Fiber.run
    ~iter:(fun () -> assert false)
    (Fiber.parallel_iter_seq (Int.Map.to_seq map) ~f:(fun (_, _) ->
         Fiber.return ()))

let%bench "Fiber.Map.parallel_map" =
  Fiber.run
    ~iter:(fun () -> assert false)
    (M.parallel_map map ~f:(fun _ x -> Fiber.return x))
  |> ignore
