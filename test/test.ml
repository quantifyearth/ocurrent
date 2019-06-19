open Current.Syntax    (* let*, let+, etc *)

module Git = Current_git_test
module Docker = Current_docker_test
module Opam = Current_opam_test

let () = Driver.init_logging ()

let fetch = Git.fetch
let build = Docker.build
let test = Docker.run ~cmd:["make"; "test"]
let push = Docker.push

let test_commit = Driver.test_commit

(* A very simple linear pipeline. Given a commit (e.g. the head of
   a PR on GitHub), this returns success if the tests pass on it. *)
let v1 commit =
  commit |> fetch |> build |> test

let test_v1 () =
  Driver.test ~name:"v1" v1 @@ function
  | 1 -> Git.complete_clone test_commit
  | 2 -> Docker.complete "image-src-123" ~cmd:["make"; "test"] @@ Ok ()
  | _ -> raise Exit

let test_v1_cancel () =
  Driver.test ~name:"v1c" v1 @@ function
  | 1 -> Git.complete_clone test_commit
  | 2 -> Driver.cancel "docker run image-src-123 make test"
  | _ -> raise Exit

(* Similar, but here the test step requires both the binary and
   the source (perhaps for the test cases). If the tests pass then
   it deploys the binary too. *)
let v2 commit =
  let src = fetch commit in
  let bin = build src in
  bin |> Current.gate ~on:(test bin) |> push ~tag:"foo/bar"

let test_v2 () =
  Driver.test ~name:"v2" v2 @@ function
  | 1 -> Git.complete_clone test_commit
  | 2 -> Docker.complete "image-src-123" ~cmd:["make"; "test"] @@ Ok ()
  | _ -> raise Exit

(* Build Linux, Mac and Windows binaries. If *all* tests pass (for
   all platforms) then deploy all binaries. *)
let v3 commit =
  let platforms = ["lin"; "mac"; "win"] in
  let src = fetch commit in
  let binaries = List.map (fun p -> p, build ~on:p src) platforms in
  let test (_p, x) = test x in
  let tests = Current.all @@ List.map test binaries in
  let gated_deploy (p, x) =
    let tag = Fmt.strf "foo/%s" p in
    x |> Current.gate ~on:tests |> push ~tag
  in
  Current.all @@ List.map gated_deploy binaries

let test_v3 () =
  Driver.test ~name:"v3" v3 @@ function
  | 1 -> Git.complete_clone test_commit
  | 2 ->
    Docker.complete "lin-image-src-123" ~cmd:["make"; "test"] @@ Ok ();
    Docker.complete "win-image-src-123" ~cmd:["make"; "test"] @@ Error (`Msg "Missing DLL");
  | _ -> raise Exit

(* Monadic bind is also available if you need to take a decision based
   on the actual source code before deciding on the rest of the pipeline.
   The let** form allows you to name the box.
   The static analysis will only show what happens up to this step until
   it actually runs, after which it will show the whole pipeline. *)
let v4 commit =
  let src = fetch commit in
  "custom-build" |>
  let** src = src in
  if Fpath.to_string src = "src-123" then build (Current.return src) |> test
  else Current.fail "Wrong hash!"

let test_v4 () =
  Driver.test ~name:"v4" v4 @@ function
  | 1 -> Git.complete_clone test_commit
  | 2 -> Docker.complete "image-src-123" ~cmd:["make"; "test"] @@ Error (`Msg "Failed")
  | _ -> raise Exit

(* The opam-repo-ci pipeline. Build the package and test it.
   If the tests pass then query for the rev-deps and build and
   test each of them. Using [list_iter] here instead of a bind
   allows us to see the whole pipeline statically, before we've
   actually calculated the rev-deps. *)
let v5 commit =
  let src = fetch commit in
  let bin = build src in
  let ok = test bin in
  Opam.revdeps src
  |> Current.gate ~on:ok
  |> Current.list_iter (fun s -> s |> fetch |> build |> test)

let test_v5 () =
  Driver.test ~name:"v5" v5 @@ function
  | 1 -> Git.complete_clone test_commit
  | 2 -> Docker.complete "image-src-123" ~cmd:["make"; "test"] @@ Ok ()
  | _ -> raise Exit

let () =
  try
    test_v1 ();
    test_v1_cancel ();
    test_v2 ();
    test_v3 ();
    test_v4 ();
    test_v5 ();
  with Failure m ->
    Fmt.pr "Tests failed!@.%s@." m;
    exit 1