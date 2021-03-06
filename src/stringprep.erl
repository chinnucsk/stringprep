%%%----------------------------------------------------------------------
%%% File    : stringprep.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : Interface to stringprep_drv
%%% Created : 16 Feb 2003 by Alexey Shchepin <alexey@proces-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2013   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(stringprep).

-author('alexey@process-one.net').

-behaviour(gen_server).

-export([start/0, start_link/0, tolower/1, nameprep/1,
	 nodeprep/1, resourceprep/1]).

%% Internal exports, call-back functions.
-export([init/1, handle_call/3, handle_cast/2,
	 handle_info/2, code_change/3, terminate/2]).

-define(STRINGPREP_PORT, stringprep_port).

-define(NAMEPREP_COMMAND, 1).

-define(NODEPREP_COMMAND, 2).

-define(RESOURCEPREP_COMMAND, 3).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],
			  []).

init([]) ->
    case load_driver() of
        ok ->
            Port = open_port({spawn, "stringprep_drv"}, []),
            register(?STRINGPREP_PORT, Port),
            {ok, Port};
        {error, Why} ->
            {stop, Why}
    end.

%%% --------------------------------------------------------
%%% The call-back functions.
%%% --------------------------------------------------------

handle_call(_, _, State) -> {noreply, State}.

handle_cast(_, State) -> {noreply, State}.

handle_info({'EXIT', Port, Reason}, Port) ->
    {stop, {port_died, Reason}, Port};
handle_info({'EXIT', _Pid, _Reason}, Port) ->
    {noreply, Port};
handle_info(_, State) -> {noreply, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_Reason, Port) ->
    catch port_close(Port),
    ok.

-spec tolower(binary()) -> binary() | error.

tolower(String) -> control(0, String).

-spec nameprep(binary()) -> binary() | error.

nameprep(String) -> control(?NAMEPREP_COMMAND, String).

-spec nodeprep(binary()) -> binary() | error.

nodeprep(String) -> control(?NODEPREP_COMMAND, String).

-spec resourceprep(binary()) -> binary() | error.

resourceprep(String) ->
    control(?RESOURCEPREP_COMMAND, String).

control(Command, String) ->
    case port_control(?STRINGPREP_PORT, Command, String) of
        <<0, _/binary>> ->
            error;
        <<1, Res/binary>> ->
            %% Result is usually a very small binary,  that fit into a heap binary.
            %% binary:copy() ensure that's the case,  instead of keeping a subbinary or
            %% refcount binary around 
            binary:copy(Res)  
    end.

load_driver() ->
    case erl_ddll:load_driver(get_so_path(), stringprep_drv) of
        ok ->
            ok;
        {error, already_loaded} ->
            ok;
        {error, ErrorDesc} = Err ->
            error_logger:error_msg("failed to load stringprep driver: ~s~n",
                                   [erl_ddll:format_error(ErrorDesc)]),
            Err
    end.

get_so_path() ->
    case os:getenv("EJABBERD_SO_PATH") of
        false ->
            case code:priv_dir(p1_stringprep) of
                {error, _} ->
                    filename:join(["priv", "lib"]);
                Path ->
                    filename:join([Path, "lib"])
            end;
        Path ->
            Path
    end.
