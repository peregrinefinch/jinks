%% SPDX-License-Identifier: Apache-2.0

%% Keep the directory exchange at the filesystem boundary. The Pooka side
%% decides which files belong to Jinks; this side supplies lstat, an exclusive
%% writer lock, and rename/rollback. No shell command gets a vote.
%%
%% read_link_info does not follow the final link:
%% https://www.erlang.org/doc/apps/kernel/file.html#read_link_info/1
%% Rename guarantees vary by operating system. This is a staged publication,
%% not a claim of a crash-durable, globally atomic directory exchange:
%% https://www.erlang.org/doc/apps/kernel/file.html#rename/2
-module(jinks_filesystem).
-include_lib("kernel/include/file.hrl").
-export([guard_tree/1, guarded/2, staged/3, create_file/3]).

guard_tree(Path) ->
    protect(fun() -> tree(text(Path)), {ok, nil} end).

guarded(Root, Relative) ->
    protect(fun() ->
        Base = filename:absname(text(Root)),
        directory(Base),
        components(Base, filename:split(text(Relative))),
        {ok, nil}
    end).

%% Open with exclusive so a competing author command cannot truncate an
%% existing source. Check links before and after creating parent directories.
%% The workspace must not be modified by a hostile concurrent process.
%% https://www.erlang.org/doc/apps/kernel/file.html#open/2
create_file(Root, Relative, Content) ->
    protect(fun() ->
        Base = filename:absname(text(Root)),
        Parts = filename:split(text(Relative)),
        directory(Base),
        components(Base, Parts),
        Target = filename:join(Base, text(Relative)),
        ensure(filelib:ensure_dir(Target), Target),
        components(Base, Parts),
        case file:open(Target, [write, exclusive, raw, binary]) of
            {ok, Device} ->
                Result = file:write(Device, Content),
                Closed = file:close(Device),
                case {Result, Closed} of
                    {ok, ok} -> {ok, nil};
                    _ ->
                        file:delete(Target),
                        ensure(Result, Target),
                        ensure(Closed, Target)
                end;
            {error, eexist} -> fail(["refusing to overwrite existing content: ", Target]);
            {error, Reason} -> io_error(Target, Reason)
        end
    end).

%% The callback receives a fresh sibling directory and the current output.
%% It may return Error without disturbing the current output. The exclusive
%% file works across separate BEAM VMs; an interrupted OS process may leave
%% the lock behind, which is deliberately reported rather than stolen.
staged(Root, Relative, Work) ->
    protect(fun() ->
        Base = filename:absname(text(Root)),
        directory(Base),
        components(Base, filename:split(text(Relative))),
        Output = filename:join(Base, text(Relative)),
        Lock = filename:join(Base, ".jinks-build.lock"),
        case file:open(Lock, [write, exclusive, raw]) of
            {ok, Device} ->
                try
                    ensure(file:write(Device, ["pid=", os:getpid(), "\n"]), Lock),
                    locked(Output, Work)
                after
                    file:close(Device),
                    file:delete(Lock)
                end;
            {error, eexist} ->
                fail("another build owns .jinks-build.lock; if its process was interrupted, remove that lock after checking no build is running");
            {error, Reason} -> io_error(Lock, Reason)
        end
    end).

locked(Output, Work) ->
    tree(Output),
    case file:read_link_info(Output) of
        {ok, #file_info{type = directory}} -> ok;
        {error, enoent} -> ok;
        {ok, _} -> fail("output must be a directory");
        {error, Reason} -> io_error(Output, Reason)
    end,
    Parent = filename:dirname(Output),
    ensure(filelib:ensure_dir(filename:join(Parent, "placeholder")), Parent),
    Token = os:getpid() ++ "-" ++ integer_to_list(erlang:unique_integer([positive]), 36),
    Stage = filename:join(Parent, ".jinks-stage-" ++ Token),
    Backup = filename:join(Parent, ".jinks-backup-" ++ Token),
    ensure(file:make_dir(Stage), Stage),
    try
        case Work(unicode:characters_to_binary(Stage), unicode:characters_to_binary(Output)) of
            {ok, nil} ->
                tree(Stage),
                publish(Stage, Output, Backup),
                {ok, nil};
            {error, _} = Error -> Error
        end
    after
        remove_tree(Stage)
    end.

publish(Stage, Output, Backup) ->
    case file:read_link_info(Backup) of
        {error, enoent} -> ok;
        _ -> fail("publication backup path already exists")
    end,
    case file:read_link_info(Output) of
        {error, enoent} -> ensure(file:rename(Stage, Output), Output);
        {ok, #file_info{type = directory}} ->
            ensure(file:rename(Output, Backup), Output),
            case file:rename(Stage, Output) of
                ok ->
                    case remove_tree(Backup) of
                        ok -> ok;
                        {error, Reason} ->
                            fail(io_lib:format("site published, but backup cleanup failed at ~ts: ~p", [Backup, Reason]))
                    end;
                {error, Reason} ->
                    case file:rename(Backup, Output) of
                        ok -> io_error(Output, Reason);
                        {error, Restore} ->
                            fail(io_lib:format("publication failed (~p); restore failed (~p); previous output is at ~ts", [Reason, Restore, Backup]))
                    end
            end;
        _ -> fail("output changed during publication; refusing to replace it")
    end.

%% Refuse links and special files, including a linked source directory. A
%% missing optional directory is fine; its caller decides whether it is needed.
tree(Path) ->
    case file:read_link_info(Path) of
        {ok, #file_info{type = directory}} ->
            case file:list_dir(Path) of
                {ok, Names} -> lists:foreach(fun(Name) -> tree(filename:join(Path, Name)) end, Names);
                {error, Reason} -> io_error(Path, Reason)
            end;
        {ok, #file_info{type = regular}} -> ok;
        {ok, #file_info{type = symlink}} -> fail(["symbolic links are not supported: ", Path]);
        {ok, _} -> fail(["special files are not supported: ", Path]);
        {error, enoent} -> ok;
        {error, Reason} -> io_error(Path, Reason)
    end.

directory(Path) ->
    case file:read_link_info(Path) of
        {ok, #file_info{type = directory}} -> ok;
        {ok, #file_info{type = symlink}} -> fail(["symbolic links are not supported: ", Path]);
        {ok, _} -> fail(["expected a directory: ", Path]);
        {error, Reason} -> io_error(Path, Reason)
    end.

components(_At, []) -> ok;
components(At, [Name | Rest]) ->
    case Name == ".." orelse Name == "." orelse filename:pathtype(Name) =/= relative of
        true -> fail("expected a contained relative path");
        false -> ok
    end,
    Next = filename:join(At, Name),
    case file:read_link_info(Next) of
        {ok, #file_info{type = symlink}} -> fail(["symbolic links are not supported: ", Next]);
        {ok, #file_info{type = directory}} -> components(Next, Rest);
        {ok, #file_info{type = regular}} when Rest == [] -> ok;
        {error, enoent} -> ok;
        {ok, _} -> fail(["expected a directory: ", Next]);
        {error, Reason} -> io_error(Next, Reason)
    end.

%% Cleanup never follows a symlink, even if a tree changed while being read.
remove_tree(Path) ->
    case file:read_link_info(Path) of
        {error, enoent} -> ok;
        {ok, #file_info{type = directory}} ->
            case file:list_dir(Path) of
                {ok, Names} ->
                    case remove_children(Path, Names) of
                        ok -> file:del_dir(Path);
                        Error -> Error
                    end;
                Error -> Error
            end;
        {ok, _} -> file:delete(Path);
        Error -> Error
    end.

remove_children(_Root, []) -> ok;
remove_children(Root, [Name | Rest]) ->
    case remove_tree(filename:join(Root, Name)) of
        ok -> remove_children(Root, Rest);
        Error -> Error
    end.

ensure(ok, _Path) -> ok;
ensure({error, Reason}, Path) -> io_error(Path, Reason).

io_error(Path, Reason) ->
    fail(io_lib:format("~ts: ~ts", [Path, file:format_error(Reason)])).

fail(Message) -> throw({jinks_io, unicode:characters_to_binary(Message)}).

protect(Work) ->
    try Work() catch throw:{jinks_io, Message} -> {error, Message} end.

text(Binary) -> unicode:characters_to_list(Binary).
