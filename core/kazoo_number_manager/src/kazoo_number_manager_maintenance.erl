%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2016-2019, 2600Hz
%%% @doc
%%% @author Pierre Fenoll
%%% @end
%%%-----------------------------------------------------------------------------
-module(kazoo_number_manager_maintenance).

-include("knm.hrl").

-export([generate_js_classifiers/1]).

-export([app_using/2]).
-export([carrier_module_usage/0
        ,carrier_module_usage/1
        ]).
-export([convert_carrier_module/2
        ,convert_carrier_module/3
        ,convert_carrier_module_number/2
        ]).
-export([refresh_numbers_dbs/0
        ,refresh_numbers_db/1
        ]).
-export([init_dbs/0
        ,register_views/0
        ]).
-export([fix_number/3
        ,fix_account_numbers/1
        ,fix_accounts_numbers/1
        ]).
-export([copy_number_dbs_to_accounts/0
        ,copy_number_dbs_to_accounts/1
        ]).
-export([copy_number_db_to_accounts/1
        ]).
-export([copy_number_to_account_db/2
        ]).
-export([copy_accounts_to_number_dbs/0, copy_accounts_to_number_dbs/1
        ,copy_account_to_number_dbs/1
        ]).
-export([remove_wrong_assigneds_from_accounts/0
        ,remove_wrong_assigneds_from_accounts/1
        ]).
-export([remove_wrong_assigneds_from_account/1
        ]).
-export([migrate/0, migrate/1
        ,migrate_unassigned_numbers/0, migrate_unassigned_numbers/1
        ]).
-export([generate_numbers/4]).
-export([delete/1]).
-export([purge_discovery/0, purge_discovery/1]).
-export([purge_deleted/0, purge_deleted/1]).
-export([update_number_services_view/1]).

-export([all_features/0]).
-export([feature_permissions_on_number/1]).
-export([add_allowed_feature_on_number/2
        ,remove_allowed_feature_on_number/2
        ,add_denied_feature_on_number/2
        ,remove_denied_feature_on_number/2
        ]).
-export([feature_permissions_on_reseller_of/1]).
-export([add_allowed_feature_on_reseller_of/2
        ,remove_allowed_feature_on_reseller_of/2
        ,add_denied_feature_on_reseller_of/2
        ,remove_denied_feature_on_reseller_of/2
        ]).
-export([feature_permissions_on_system_config/0]).
-export([add_allowed_feature_on_system_config/1
        ,remove_allowed_feature_on_system_config/1
        ,reset_allowed_features_to_defaults_on_system_config/0
        ]).
-export([ensure_adminonly_features_are_reachable/0]).

-export([migrate_port_requests/0]).

-define(TIME_BETWEEN_ACCOUNTS_MS
       ,kapps_config:get_pos_integer(?KNM_CONFIG_CAT, <<"time_between_accounts_ms">>, ?MILLISECONDS_IN_SECOND)).

-define(TIME_BETWEEN_NUMBERS_MS
       ,kapps_config:get_pos_integer(?KNM_CONFIG_CAT, <<"time_between_numbers_ms">>, ?MILLISECONDS_IN_SECOND)).

-define(PARALLEL_JOBS_COUNT
       ,kapps_config:get_pos_integer(?KNM_CONFIG_CAT, <<"parallel_jobs_count">>, 1)
       ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec carrier_module_usage() -> 'ok'.
carrier_module_usage() ->
    carrier_module_usage(knm_util:get_all_number_dbs(), dict:new()).

-spec carrier_module_usage(kz_term:text()) -> 'ok'.
carrier_module_usage(Prefix) ->
    Database = knm_converters:to_db(Prefix),
    carrier_module_usage([Database], dict:new()).

-spec carrier_module_usage(kz_term:ne_binaries(), dict:dict()) -> 'ok'.
carrier_module_usage([], Totals) ->
    io:format("Totals:~n", []),
    F = fun (Module, Count) -> io:format("    ~s: ~p~n", [Module, Count]) end,
    _ = dict:map(F, Totals),
    ok;
carrier_module_usage([Database|Databases], Totals0) ->
    Totals1 = get_carrier_module_usage(Database, Totals0),
    carrier_module_usage(Databases, Totals1).

-spec get_carrier_module_usage(kz_term:ne_binary(), dict:dict()) -> dict:dict().
get_carrier_module_usage(Database, Totals) ->
    io:format("~s:~n", [Database]),
    ViewOptions = ['reduce', 'group'],
    {'ok', JObjs} = kz_datamgr:get_results(Database, <<"numbers/module_name">>, ViewOptions),
    log_carrier_module_usage(JObjs, Database, Totals).

-spec log_carrier_module_usage(kz_json:objects(), kz_term:ne_binary(), dict:dict()) -> dict:dict().
log_carrier_module_usage([], _, Totals) -> Totals;
log_carrier_module_usage([JObj|JObjs], Database, Totals0) ->
    Module = kz_json:get_value(<<"key">>, JObj),
    Count = kz_json:get_value(<<"value">>, JObj),
    io:format("    ~s: ~p~n", [Module, Count]),
    Totals1 = dict:update_counter(Module, Count, Totals0),
    log_carrier_module_usage(JObjs, Database, Totals1).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec convert_carrier_module(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
convert_carrier_module(Source, Target) ->
    convert_carrier_module_database(Source, Target, knm_util:get_all_number_dbs()).

-spec convert_carrier_module(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
convert_carrier_module(Source, Target, Prefix) ->
    Database = knm_converters:to_db(Prefix),
    convert_carrier_module_database(Source, Target, [Database]).

-spec convert_carrier_module_database(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binaries()) -> 'ok'.
convert_carrier_module_database(_, _, []) -> 'ok';
convert_carrier_module_database(Source, Target, [Database|Databases]) ->
    io:format("attempt to convert numbers with carrier module ~s to ~s in database ~s~n"
             ,[Source, Target, Database]),
    ViewOptions = [{'reduce', 'false'}, {'key', Source}],
    {'ok', JObjs} = kz_datamgr:get_results(Database, <<"numbers/module_name">>, ViewOptions),
    convert_carrier_module_numbers([kz_doc:id(JObj) || JObj <- JObjs], Target),
    convert_carrier_module_database(Source, Target, Databases).

-spec convert_carrier_module_numbers(kz_term:ne_binaries(), kz_term:ne_binary()) -> 'ok'.
convert_carrier_module_numbers(Nums, Target) ->
    case lists:member(Target, knm_carriers:all_modules()) of
        'false' -> io:format("Bad carrier module: ~s\n", [Target]);
        'true' ->
            Routines = [{fun knm_phone_number:set_module_name/2, Target}],
            #{ok := Ns, ko := KOs} = knm_numbers:update(Nums, Routines),
            TotalLength = length(Nums),
            print_convert_carrier_success(Target, TotalLength, Ns),
            print_convert_carrier_failure(Target, TotalLength, KOs)
    end.

-spec print_convert_carrier_success(kz_term:ne_binary(), non_neg_integer(), kz_term:ne_binaries()) -> 'ok'.
print_convert_carrier_success(_, _, []) -> 'ok';
print_convert_carrier_success(Target, TotalLength, Converted) ->
    io:format("updated carrier module to ~s for ~b/~b number(s):\n", [Target, length(Converted), TotalLength]),
    F = fun (N) -> io:format("\t~s\n", [knm_phone_number:number(knm_number:phone_number(N))]) end,
    lists:foreach(F, Converted).

-spec print_convert_carrier_failure(kz_term:ne_binary(), non_neg_integer(), map()) -> 'ok'.
print_convert_carrier_failure(Target, TotalLength, KOs) ->
    case maps:size(KOs) of
        0 -> 'ok';
        KOsSize ->
            io:format("updating carrier module to ~s failed for ~b/~b number(s):\n", [Target, KOsSize, TotalLength]),
            F = fun (Num, R) -> io:format("\t~s: ~p\n", [Num, R]) end,
            _ = maps:map(F, KOs),
            'ok'
    end.

-spec convert_carrier_module_number(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
convert_carrier_module_number(Num, Target) ->
    convert_carrier_module_numbers([Num], Target).

-spec init_dbs() -> 'ok'.
init_dbs() ->
    init_dbs([?KZ_MANAGED_DB
             ,?KZ_INUM_DB
             ,?KZ_PORT_REQUESTS_DB
             ]).

init_dbs([]) -> 'ok';
init_dbs([Db | Dbs]) ->
    case kz_datamgr:db_exists(Db) of
        'false' ->
            Result = kz_datamgr:db_create(Db),
            lager:debug("~s is created: ~p", [Db, Result]);
        'true' -> 'ok'
    end,
    _ = kapps_maintenance:refresh(Db),
    init_dbs(Dbs).

-spec register_views() -> 'ok'.
register_views() ->
    kz_datamgr:register_views_from_folder(?APP).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec refresh_numbers_dbs() -> 'ok'.
refresh_numbers_dbs() ->
    NumberDbs = knm_util:get_all_number_dbs(),
    refresh_numbers_dbs(NumberDbs, length(NumberDbs)).

-spec refresh_numbers_dbs(kz_term:ne_binaries(), non_neg_integer()) -> 'ok'.
refresh_numbers_dbs([], _) -> 'ok';
refresh_numbers_dbs([NumberDb|NumberDbs], Total) ->
    ?SUP_LOG_DEBUG("(~p/~p) updating number db ~s", [length(NumberDbs) + 1, Total, NumberDb]),
    _ = refresh_numbers_db(NumberDb),
    refresh_numbers_dbs(NumberDbs, Total).

-spec refresh_numbers_db(kz_term:ne_binary()) -> 'ok'.
refresh_numbers_db(<<?KNM_DB_PREFIX_ENCODED, _/binary>> = NumberDb) ->
    _ = kapps_maintenance:refresh(NumberDb),
    'ok';
refresh_numbers_db(<<?KNM_DB_PREFIX, Suffix/binary>>) ->
    NumberDb = <<?KNM_DB_PREFIX_ENCODED, Suffix/binary>>,
    refresh_numbers_db(NumberDb);
refresh_numbers_db(<<"+", _/binary>> = Num) ->
    refresh_numbers_db(knm_converters:to_db(Num));
refresh_numbers_db(_Thing) ->
    ?SUP_LOG_DEBUG("skipping badly formed ~s", [_Thing]).

-spec update_number_services_view(kz_term:ne_binary()) -> no_return.
update_number_services_view(?MATCH_ACCOUNT_RAW(AccountId)) ->
    update_number_services_view(kz_util:format_account_db(AccountId));
update_number_services_view(?MATCH_ACCOUNT_ENCODED(_)=AccountDb) ->
    FunMatchBlock = fun(Class) -> ["    resC['", Class, "'] = resM;"] end,
    MapView = number_services_map(FunMatchBlock),
    RedView = number_services_red(),
    ViewName = <<"_design/numbers">>,
    View = case kz_datamgr:open_doc(AccountDb, ViewName) of
               {'ok', JObj} -> JObj;
               {'error', _R} ->
                   lager:debug("reading account view ~s from disk (~p)", [ViewName, _R]),
                   {ViewName,JObj} = kapps_util:get_view_json('crossbar', <<"account/numbers.json">>),
                   JObj
           end,
    PathMap = [<<"views">>, <<"reconcile_services">>, <<"map">>],
    PathRed = [<<"views">>, <<"reconcile_services">>, <<"reduce">>],
    case MapView =:= kz_json:get_ne_binary_value(PathMap, View)
        andalso RedView =:= kz_json:get_ne_binary_value(PathRed, View)
    of
        'true' -> 'no_return';
        'false' ->
            NewView = kz_json:set_values([{PathMap, MapView}
                                         ,{PathRed, RedView}
                                         ]
                                        ,View
                                        ),
            _Updated = kz_datamgr:db_view_update(AccountDb, [{ViewName, NewView}]),
            ?SUP_LOG_DEBUG("view updated for '~s': ~p", [AccountDb, _Updated])
    end.


-spec fix_accounts_numbers([kz_term:ne_binary()]) -> 'ok'.
fix_accounts_numbers(Accounts) ->
    AccountDbs = lists:usort([kz_util:format_account_db(Account) || Account <- Accounts]),
    _ = purge_discovery(),
    _ = purge_deleted(),
    foreach_pause_in_between(?TIME_BETWEEN_ACCOUNTS_MS, fun fix_account_numbers/1, AccountDbs).

-spec fix_account_numbers(kz_term:ne_binary()) -> 'ok'.
fix_account_numbers(AccountDb = ?MATCH_ACCOUNT_ENCODED(A,B,Rest)) ->
    ?SUP_LOG_DEBUG("########## fixing [~s] ##########", [AccountDb]),
    ?SUP_LOG_DEBUG("[~s] getting numbers from account db", [AccountDb]),
    DisplayPNs = get_DIDs(AccountDb, <<"phone_numbers/crossbar_listing">>),
    put(callflow_DIDs, get_DIDs_callflow(AccountDb)),
    put(trunkstore_DIDs, get_DIDs_trunkstore(AccountDb)),
    AccountId = ?MATCH_ACCOUNT_RAW(A, B, Rest),

    Malt = [1
           ,{processes, schedulers}
           ],
    Leftovers =
        plists:fold(fun (NumberDb, Leftovers) ->
                            Fixer = fun (DID) -> fix_docs(AccountDb, NumberDb, DID) end,
                            ?SUP_LOG_DEBUG("[~s] getting numbers from ~s", [AccountDb, NumberDb]),
                            AuthoritativePNs = get_DIDs_assigned_to(NumberDb, AccountId),
                            ?SUP_LOG_DEBUG("[~s] start fixing ~s", [AccountDb, NumberDb]),
                            foreach_pause_in_between(?TIME_BETWEEN_NUMBERS_MS
                                                    ,Fixer
                                                    ,gb_sets:to_list(AuthoritativePNs)
                                                    ),
                            ?SUP_LOG_DEBUG("[~s] done fixing ~s", [AccountDb, NumberDb]),
                            %% timer:sleep(?TIME_BETWEEN_ACCOUNTS_MS),
                            gb_sets:subtract(Leftovers, AuthoritativePNs)
                    end
                   ,fun gb_sets:intersection/2
                   ,DisplayPNs
                   ,knm_util:get_all_number_dbs()
                   ,Malt
                   ),

    ToRm0 = case Leftovers =:= [] of
                'true' ->
                    %% Only if there is no number_dbs, plists would return empty list
                    %% regardless of initAcc value. See `plists:fuse/2'.
                    [];
                'false' -> gb_sets:to_list(Leftovers)
            end,
    lists:foreach(fun (_DID) -> log_alien(AccountDb, _DID) end, ToRm0),
    ToRm = [DID
            || DID <- ToRm0,
               'false' =:= is_assigned_to(AccountDb, DID, AccountId),
               ok =:= ?SUP_LOG_DEBUG("########## will remove [~s] doc: ~s ##########", [AccountDb, DID])
           ],
    _ = kz_datamgr:del_docs(AccountDb, ToRm),
    ?SUP_LOG_DEBUG("########## updating view [~s] ##########", [AccountDb]),
    update_number_services_view(AccountDb),
    erase(callflow_DIDs),
    erase(trunkstore_DIDs),
    ?SUP_LOG_DEBUG("########## done fixing [~s] ##########", [AccountDb]);
fix_account_numbers(Account = ?NE_BINARY) ->
    fix_account_numbers(kz_util:format_account_db(Account)).

log_alien(_AccountDb, _DID) ->
    ?SUP_LOG_DEBUG("########## found alien [~s] doc: ~s ##########", [_AccountDb, _DID]).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec copy_accounts_to_number_dbs() -> 'ok'.
copy_accounts_to_number_dbs() ->
    AccountDbs = kapps_util:get_all_accounts('encoded'),
    ?SUP_LOG_DEBUG("::: start copying numbers doc from ~b account dbs to number dbs", [length(AccountDbs)]),
    copy_accounts_to_number_dbs(AccountDbs, length(AccountDbs), ?TIME_BETWEEN_ACCOUNTS_MS).

-spec copy_accounts_to_number_dbs(kz_term:ne_binaries()) -> 'ok'.
copy_accounts_to_number_dbs(Accounts) ->
    ?SUP_LOG_DEBUG("::: start copying numbers doc from ~b account dbs to number dbs", [length(Accounts)]),
    copy_accounts_to_number_dbs(Accounts, length(Accounts), ?TIME_BETWEEN_ACCOUNTS_MS).

-spec copy_accounts_to_number_dbs(kz_term:ne_binaries(), non_neg_integer(), non_neg_integer()) -> 'ok'.
copy_accounts_to_number_dbs([], _, _) ->
    'ok';
copy_accounts_to_number_dbs([AccountDb|AccountDbs], Total, SleepTime) ->
    ?SUP_LOG_DEBUG("(~p/~p) copying numbers from '~s' to number dbs~n"
                  ,[length(AccountDbs) + 1, Total, kz_util:format_account_db(AccountDb)]
                  ),
    copy_account_to_number_dbs(AccountDb),
    _ = timer:sleep(SleepTime),
    copy_accounts_to_number_dbs(AccountDbs, Total, SleepTime).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec copy_account_to_number_dbs(kz_term:ne_binary()) -> 'ok'.
copy_account_to_number_dbs(Account) ->
    AccountDb = kz_util:format_account_db(Account),
    ViewOptions = [{'limit', 200}
                  ,'include_docs'
                  ],
    View = <<"numbers/list_by_number">>,
    get_results_loop(AccountDb, View, ViewOptions, fun split_and_save_to_number_dbs/2).

-spec split_and_save_to_number_dbs(kz_term:ne_binary(), kz_json:objects()) -> 'ok'.
split_and_save_to_number_dbs(AccountDb, Results) ->
    F = fun (JObj, M) ->
                NewJObj = kz_json:get_value(<<"doc">>, JObj),
                NumberDb = knm_converters:to_db(knm_converters:normalize(kz_doc:id(NewJObj))),
                M#{NumberDb => [kz_doc:delete_revision(NewJObj) | maps:get(NumberDb, M, [])]}
        end,
    Map = lists:foldl(F, #{}, Results),
    save_to_number_dbs(AccountDb, maps:to_list(Map), 1).

-spec save_to_number_dbs(kz_term:ne_binary(), kz_term:proplist(), integer()) -> 'ok'.
save_to_number_dbs(_, [], _) -> 'ok';
save_to_number_dbs(_AccountDb, _, Retries) when Retries < 0 ->
    ?SUP_LOG_DEBUG("  - reached to maximum retries to save to number dbs in this batch");
save_to_number_dbs(AccountDb, [{Db, JObjs} | Rest], Retries) ->
    case kz_datamgr:save_docs(Db, JObjs) of
        {'ok', Saved} ->
            log_save_failures(<<"  - failed to save some numbers in ", Db/binary, ": ">>
                             ,Saved
                             ),
            save_to_number_dbs(AccountDb, Rest, Retries);
        {'error', 'not_found'} ->
            ?SUP_LOG_DEBUG("  - creating number db ~s", [Db]),
            _ = kz_datamgr:db_create(Db),
            _ = kapps_maintenance:refresh(Db),
            save_to_number_dbs(AccountDb, [{Db, JObjs} | Rest], Retries - 1);
        {'error', 'timeout'} ->
            ?SUP_LOG_ERROR("  - timeout to save to ~s, maybe trying again...", [Db]),
            save_to_number_dbs(AccountDb, [{Db, JObjs} | Rest], Retries - 1);
        {'error', _Reason} ->
            ?SUP_LOG_ERROR("  - failed to save numbers to ~s: ~p", [Db, _Reason])
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec copy_number_dbs_to_accounts() -> 'ok'.
copy_number_dbs_to_accounts() ->
    NumberDbs = knm_util:get_all_number_dbs(),
    ?SUP_LOG_DEBUG("::: start copying numbers doc from ~b number dbs to account dbs", [length(NumberDbs)]),
    copy_number_dbs_to_accounts(NumberDbs, length(NumberDbs), ?TIME_BETWEEN_ACCOUNTS_MS).

-spec copy_number_dbs_to_accounts(kz_term:ne_binaries()) -> 'ok'.
copy_number_dbs_to_accounts(NumberDbs) ->
    ?SUP_LOG_DEBUG("::: start copying numbers doc from ~b number dbs to account dbs", [length(NumberDbs)]),
    copy_number_dbs_to_accounts(NumberDbs, length(NumberDbs), ?TIME_BETWEEN_ACCOUNTS_MS).

-spec copy_number_dbs_to_accounts(kz_term:ne_binaries(), non_neg_integer(), non_neg_integer()) -> 'ok'.
copy_number_dbs_to_accounts([], _, _) ->
    'ok';
copy_number_dbs_to_accounts([NumberDb|NumberDbs], Total, SleepTime) ->
    ?SUP_LOG_DEBUG("(~p/~p) copying numbers from '~s' to account dbs~n"
                  ,[length(NumberDbs) + 1, Total, NumberDb]
                  ),
    copy_number_db_to_accounts(NumberDb),
    _ = timer:sleep(SleepTime),
    copy_number_dbs_to_accounts(NumberDbs, Total, SleepTime).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec copy_number_db_to_accounts(kz_term:ne_binary()) -> 'ok'.
copy_number_db_to_accounts(NumberDb) ->
    ViewOptions = [{'limit', 200}
                  ,'include_docs'
                  ],
    View = <<"numbers/assigned_to">>,
    get_results_loop(NumberDb, View, ViewOptions, fun(_Db, R) -> split_and_save_to_account_dbs(R) end).

-spec split_and_save_to_account_dbs(kz_json:objects()) -> 'ok'.
split_and_save_to_account_dbs(Results) ->
    F = fun (JObj, M) ->
                Doc = kz_json:get_value(<<"doc">>, JObj),
                AccountId = kz_json:get_value(<<"pvt_assigned_to">>, Doc),
                M#{AccountId => [kz_doc:delete_revision(Doc) | maps:get(AccountId, M, [])]}
        end,
    Map = lists:foldl(F, #{}, Results),
    save_to_account_db(maps:to_list(Map), 1).

-spec save_to_account_db(kz_term:proplist(), integer()) -> 'ok'.
save_to_account_db([], _) -> 'ok';
save_to_account_db(_, Retries) when Retries < 0 ->
    ?SUP_LOG_DEBUG("  - reached to maximum retries to save to number dbs in this batch");
save_to_account_db([{AccountId, JObjs} | Rest], Retries) ->
    case kz_datamgr:save_docs(kz_util:format_account_db(AccountId), JObjs) of
        {'ok', Saved} ->
            handle_save_to_account_db(AccountId, JObjs, split_by_failed_reasons(Saved, #{})),
            save_to_account_db(Rest, Retries);
        {'error', 'timeout'} ->
            ?SUP_LOG_ERROR("  - timeout to save to ~s, maybe trying again...", [AccountId]),
            save_to_account_db([{AccountId, JObjs} | Rest], Retries - 1);
        {'error', _Reason} ->
            ?SUP_LOG_ERROR("  - failed to save numbers to account ~s: ~p", [AccountId, _Reason])
    end.

-spec handle_save_to_account_db(kz_term:ne_binary(), kz_json:objects(), map()) -> 'ok'.
handle_save_to_account_db(AccountId, JObjs, #{<<"conflict">> := Conflicts}=Failed) ->
    FailedAgain = save_conflict_to_account_db(AccountId, JObjs, Conflicts),
    Message = <<"  - failed to save some numbers in account ", AccountId/binary, " db: ">>,
    log_save_failures(Message, maps:merge(Failed, FailedAgain));
handle_save_to_account_db(AccountId, _, Failed) ->
    Message = <<"  - failed to save some numbers in account ", AccountId/binary, " db: ">>,
    log_save_failures(Message, Failed).

-spec save_conflict_to_account_db(kz_term:ne_binary(), kz_json:objects(), kz_term:ne_binaries()) -> map().
save_conflict_to_account_db(AccountId, JObjs, ConflictIds) ->
    AccountDb = kz_util:format_account_db(AccountId),
    ConflictIdsSet = gb_sets:from_list(ConflictIds),
    {Errored, OpenedIds, Revs} = get_conflicts_revs_from_account(AccountDb, ConflictIds),
    ConflictJObjs = [kz_doc:set_revision(JObj, maps:get(kz_doc:id(JObj), Revs))
                     || JObj <- JObjs,
                        gb_sets:is_member(kz_doc:id(JObj), ConflictIdsSet),
                        gb_sets:is_member(kz_doc:id(JObj), OpenedIds)
                    ],
    case kz_datamgr:save_docs(AccountDb, ConflictJObjs) of
        {'ok', Saved} ->
            split_by_failed_reasons(Saved, Errored);
        {'error', Err} ->
            Reason = kz_term:safe_cast(Err, <<"datastore_fault">>, fun kz_term:to_binary/1),
            Errored#{Reason => maps:get(Reason, Errored, []) ++ [Id || Id <- ConflictIds]}
    end.

-spec get_conflicts_revs_from_account(kz_term:ne_binary(), kz_term:ne_binaries()) ->
                                             {map(), gb_sets:set(), map()}.
get_conflicts_revs_from_account(AccountDb, ConflictIds) ->
    case kz_datamgr:open_docs(AccountDb, ConflictIds) of
        {'ok', JObjs} ->
            split_errors_opened_revs(JObjs, {#{}, gb_sets:new(), #{}});
        {'error', Err} ->
            Reason = kz_term:safe_cast(Err, <<"datastore_fault">>, fun kz_term:to_binary/1),
            [{Id, Reason} || Id <- ConflictIds]
    end.

-spec split_errors_opened_revs(kz_json:objects(), {map(), gb_sets:set(), map()}) ->
                                      {map(), gb_sets:set(), map()}.
split_errors_opened_revs([], Acc) -> Acc;
split_errors_opened_revs([JObj|JObjs], {Errors, Opened, Revs}) ->
    case kz_json:get_value(<<"error">>, JObj) of
        'undefined' ->
            Id = kz_doc:id(JObj),
            Acc = {Errors
                  ,gb_sets:add_element(Id, Opened)
                  ,Revs#{Id => kz_doc:revision(kz_json:get_value(<<"doc">>, JObj))}
                  },
            split_errors_opened_revs(JObjs, Acc);
        Err ->
            Reason = kz_term:safe_cast(Err, <<"datastore_fault">>, fun kz_term:to_binary/1),
            Acc = {Errors#{Reason => [kz_doc:id(JObj)|maps:get(Reason, Errors, [])]}
                  ,Opened
                  ,Revs
                  },
            split_errors_opened_revs(JObjs, Acc)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec copy_number_to_account_db(kz_term:ne_binary(), kz_term:ne_binary()) -> {'ok' | 'error', kz_term:ne_binary()}.
copy_number_to_account_db(Num, Account) ->
    AccountId = kz_util:format_account_id(Account),
    AccountDb = kz_util:format_account_db(AccountId),
    Number = knm_converters:normalize(Num),
    NumberDb = knm_converters:to_db(Number),
    case kz_datamgr:open_doc(NumberDb, Number) of
        {'ok', JObj} ->
            NewJObj = case kz_datamgr:lookup_doc_rev(AccountDb, kz_doc:id(JObj)) of
                          {'ok', Rev} -> kz_doc:set_revision(JObj, Rev);
                          {'error', _} -> kz_doc:delete_revision(JObj)
                      end,
            case kz_datamgr:save_doc(AccountDb, NewJObj) of
                {'ok', _} -> {'ok', kz_doc:id(JObj)};
                {'error', Reason} ->
                    Error = kz_term:to_binary(
                              io_lib:format("can save number '~s' to account db: ~p", [kz_doc:id(JObj), Reason])
                             ),
                    {'error', Error}
            end;
        {'error', Reason} ->
            Error = kz_term:to_binary(
                      io_lib:format("can read number '~s' from '~s': ~p", [Number, NumberDb, Reason])
                     ),
            {'error', Error}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec remove_wrong_assigneds_from_accounts() -> 'ok'.
remove_wrong_assigneds_from_accounts() ->
    AccountDbs = kapps_util:get_all_accounts('encoded'),
    ?SUP_LOG_DEBUG("::: start removing wrong assigned numbers from ~b account dbs", [length(AccountDbs)]),
    remove_wrong_assigneds_from_accounts(AccountDbs, length(AccountDbs), ?TIME_BETWEEN_ACCOUNTS_MS).

-spec remove_wrong_assigneds_from_accounts(kz_term:ne_binaries()) -> 'ok'.
remove_wrong_assigneds_from_accounts(Accounts) ->
    ?SUP_LOG_DEBUG("::: start removing wrong assigned numbers from ~b account dbs", [length(Accounts)]),
    remove_wrong_assigneds_from_accounts(accounts, length(Accounts), ?TIME_BETWEEN_ACCOUNTS_MS).

-spec remove_wrong_assigneds_from_accounts(kz_term:ne_binaries(), non_neg_integer(), non_neg_integer()) -> 'ok'.
remove_wrong_assigneds_from_accounts([], _, _) ->
    'ok';
remove_wrong_assigneds_from_accounts([AccountDb|AccountDbs], Total, SleepTime) ->
    ?SUP_LOG_DEBUG("(~p/~p) removing wrong assigned from account ~s~n"
                  ,[length(AccountDbs) + 1, Total, kz_util:format_account_db(AccountDb)]
                  ),
    remove_wrong_assigneds_from_account(AccountDb),
    _ = timer:sleep(SleepTime),
    remove_wrong_assigneds_from_accounts(AccountDbs, Total, SleepTime).

-spec remove_wrong_assigneds_from_account(kz_term:ne_binary()) -> 'ok'.
remove_wrong_assigneds_from_account(Account) ->
    AccountDb = kz_util:format_account_db(Account),
    ViewOptions = [{'limit', 200}
                  ,'include_docs'
                  ],
    View = <<"numbers/list_by_number">>,
    get_results_loop(AccountDb, View, ViewOptions, fun remove_wrong_assigneds_from_account/2).

-spec remove_wrong_assigneds_from_account(kz_term:ne_binary(), kz_json:objects()) -> 'ok'.
remove_wrong_assigneds_from_account(_, []) -> 'ok';
remove_wrong_assigneds_from_account(AccountDb, JObjs) ->
    AccountId = kz_util:format_account_id(AccountDb),
    ToRemove = [kz_doc:id(JObj)
                || JObj <- JObjs,
                   kz_json:get_value(<<"pvt_assigned_to">>, JObj) =/= AccountId
               ],
    _ = kz_datamgr:del_docs(AccountDb, ToRemove),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_results_loop(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:proplist(), function()) -> 'ok'.
get_results_loop(Db, View, ViewOptions, CallBackFun) ->
    get_results_loop(Db, View, ViewOptions, CallBackFun, 2).

-spec get_results_loop(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:proplist(), function(), integer()) -> 'ok'.
get_results_loop(_, _View, _, _, Retries) when Retries =< 0 ->
    ?SUP_LOG_DEBUG("  - maximum retries to get read docs from ~s", [_View]);
get_results_loop(Db, View, ViewOptions, CallBackFun, Retries) ->
    Results = kz_datamgr:get_results(Db, View, ViewOptions),
    handle_get_results(Db, View, ViewOptions, CallBackFun, Retries, Results).

-spec handle_get_results(kz_term:ne_binary()
                        ,kz_term:ne_binary()
                        ,kz_term:proplist()
                        ,function()
                        ,integer()
                        ,kazoo_data:get_results_return()
                        ) -> 'ok'.
handle_get_results(Db, View, ViewOptions, CallBackFun, Retries, {'ok', JObjs}) ->
    try lists:split(props:get_integer_value('limit', ViewOptions), JObjs) of
        {Results, []} ->
            CallBackFun(Db, Results);
        {Results, [NextJObj]} ->
            CallBackFun(Db, Results),
            NewViewOptions = props:set_value('startkey', kz_doc:id(NextJObj), ViewOptions),
            get_results_loop(Db, View, NewViewOptions, CallBackFun, Retries)
    catch
        'error':'badarg' ->
            CallBackFun(Db, JObjs)
    end;
handle_get_results(Db, View, ViewOptions, CallBackFun, Retries, {'error', _Reason}) ->
    ?SUP_LOG_DEBUG("  - failed to get numbers from db ~s(~p), maybe trying again...", [Db, _Reason]),
    get_results_loop(Db, View, ViewOptions, CallBackFun, Retries - 1).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec log_save_failures(kz_term:ne_binary(), kz_json:objects() | map()) -> 'ok'.
log_save_failures(_, []) -> 'ok';
log_save_failures(_, Failed) when is_map(Failed)
                                  andalso map_size(Failed) =:= 0 ->
    'ok';
log_save_failures(Message, Failed) when is_map(Failed) ->
    Map = maps:fold(fun(Reason, Ids, Acc) ->
                            [kz_term:to_binary(io_lib:format("[~s: ~b]", [Reason, length(Ids)])) | Acc]
                    end
                   ,[]
                   ,Failed
                   ),
    ?SUP_LOG_DEBUG("~s, ~s", [Message, kz_binary:join(Map, <<", ">>)]);
log_save_failures(Message, JObjs) ->
    log_save_failures(Message, split_by_failed_reasons(JObjs, #{})).

-spec split_by_failed_reasons(kz_json:objects(), map()) -> map().
split_by_failed_reasons([], Acc) -> Acc;
split_by_failed_reasons([JObj|JObjs], Acc) ->
    case kz_json:get_value(<<"error">>, JObj) of
        'undefined' -> split_by_failed_reasons(JObjs, Acc);
        Error ->
            Reason = kz_term:to_binary(Error),
            split_by_failed_reasons(JObjs, Acc#{Reason => [kz_doc:id(JObj) | maps:get(Reason, Acc, [])]})
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec fix_number(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> knm_number_return().
fix_number(Num, AuthBy, AccountDb) ->
    Options = [{auth_by, AuthBy}
              ,{dry_run, 'false'}
              ,{batch_run, 'false'}
              ],
    NumberDb = knm_converters:to_db(knm_converters:normalize(Num)),
    case fix_docs(AccountDb, NumberDb, Num) of
        'ok' -> knm_number:get(Num, Options);
        Error -> Error
    end.

-spec migrate() -> 'ok'.
migrate() ->
    lager:info("ensuring admin-only features"),
    ensure_adminonly_features_are_reachable(),
    lager:info("refreshing number dbs"),
    _ = refresh_numbers_dbs(),
    lager:info("migrating all accounts"),
    pforeach(fun migrate/1, kapps_util:get_all_accounts()),
    lager:info("migrating unassigned numbers"),
    migrate_unassigned_numbers().

-spec migrate(kz_term:ne_binary()) -> 'ok'.
migrate(Account) ->
    AccountDb = kz_util:format_account_db(Account),
    lager:info("  ~s: fixing account numbers", [Account]),
    fix_account_numbers(AccountDb),
    lager:info("  ~s: deleting phone numbers doc", [Account]),
    _ = kz_datamgr:del_doc(AccountDb, <<"phone_numbers">>),
    lager:info("  ~s: finished", [Account]).

-spec migrate_unassigned_numbers() -> 'ok'.
migrate_unassigned_numbers() ->
    ?SUP_LOG_DEBUG("********** fixing unassigned numbers **********", []),
    pforeach(fun migrate_unassigned_numbers/1, knm_util:get_all_number_dbs()),
    ?SUP_LOG_DEBUG("********** finished fixing unassigned numbers **********", []).

-spec migrate_unassigned_numbers(kz_term:ne_binary()) -> ok.
migrate_unassigned_numbers(<<?KNM_DB_PREFIX_ENCODED, _/binary>> = NumberDb) ->
    ?SUP_LOG_DEBUG("########## start fixing ~s ##########", [NumberDb]),
    migrate_unassigned_numbers(NumberDb, 0),
    ?SUP_LOG_DEBUG("########## done fixing ~s ##########", [NumberDb]);
migrate_unassigned_numbers(<<?KNM_DB_PREFIX_encoded, Suffix/binary>>) ->
    migrate_unassigned_numbers(<<?KNM_DB_PREFIX_ENCODED, Suffix/binary>>);
migrate_unassigned_numbers(<<?KNM_DB_PREFIX, Suffix/binary>>) ->
    migrate_unassigned_numbers(<<?KNM_DB_PREFIX_ENCODED, Suffix/binary>>);
migrate_unassigned_numbers(Number) ->
    migrate_unassigned_numbers(knm_converters:to_db(Number)).

-spec migrate_unassigned_numbers(kz_term:ne_binary(), integer()) -> 'ok'.
migrate_unassigned_numbers(NumberDb, Offset) ->
    ViewOptions = [{limit, kz_datamgr:max_bulk_insert()}
                  ,{skip, Offset}
                  ],
    ?SUP_LOG_DEBUG("[~s] checking for unassigned numbers with offset ~b", [NumberDb, Offset]),
    case kz_datamgr:get_results(NumberDb, <<"numbers/unassigned">>, ViewOptions) of
        {ok, []} -> 'ok';
        {ok, JObjs} ->
            Length = length(JObjs),
            ?SUP_LOG_DEBUG("[~s] fixing ~b docs", [NumberDb, Length]),
            foreach_pause_in_between(?TIME_BETWEEN_NUMBERS_MS
                                    ,fun fix_unassign_doc/1
                                    ,[kz_doc:id(JObj) || JObj <- JObjs]
                                    ),
            timer:sleep(?TIME_BETWEEN_ACCOUNTS_MS),
            migrate_unassigned_numbers(NumberDb, Offset + Length);
        {error, _R} ->
            ?SUP_LOG_DEBUG("failed to get unassigned DIDs from ~s: ~p", [NumberDb, _R])
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec escape(kz_term:ne_binary()) -> kz_term:ne_binary().
escape(?NE_BINARY=Bin0) ->
    StartSz = byte_size(Start= <<"<<">>),
    EndSz   = byte_size(End  = <<">>">>),
    Bin = iolist_to_binary(io_lib:format("~p", [Bin0])),
    SizeOfWhatIWant = byte_size(Bin) - (StartSz + EndSz),
    <<Start:StartSz/binary, Escaped:SizeOfWhatIWant/binary, End:EndSz/binary>> = Bin,
    Escaped.

-type js_match_block() :: fun((kz_term:ne_binary()) -> iolist()).
-spec number_services_map(js_match_block()) -> kz_term:ne_binary().
number_services_map(FunMatchBlock) ->
    iolist_to_binary(
      ["function(doc) {"
       "  if (doc.pvt_type != 'number' || doc.pvt_deleted) return;"
       "  var resM = {};"
       "  resM[doc.pvt_module_name] = 1;"
       "  var resC = {};"
      ,generate_js_classifiers(FunMatchBlock),
       "  var resF = {};"
       "  var used = doc.pvt_features || {};"
       "  for (var feature in used)"
       "    if (used.hasOwnProperty(feature))"
       "      resF[feature] = 1;"
       "  emit(doc._id, {'classifications':resC, 'features':resF});"
       "}"
      ]).

-spec generate_js_classifiers(js_match_block()) -> iolist().
generate_js_classifiers(FunMatchBlock) ->
    ClassifiersJObj = knm_converters:available_classifiers(), %%TODO: per-account classifiers.
    Pairs = [{Classification, kz_json:get_value([Classification, <<"regex">>], ClassifiersJObj)}
             || Classification <- kz_json:get_keys(ClassifiersJObj)
            ],
    {Classifications, Regexs} = lists:unzip(Pairs),
    generate_js_classifiers(Classifications, Regexs, FunMatchBlock).

-spec generate_js_classifiers(kz_term:ne_binaries(), kz_term:ne_binaries(), js_match_block()) -> iolist().
generate_js_classifiers(Classifications, Regexs, FunMatchBlock) ->
    ["  var e164 = doc._id;"
     "  if (false) return;"
    ,[["  else if (e164.match(", escape(Regex), "))"
      ,FunMatchBlock(Class)
      ]
      || {Class, Regex} <- lists:zip(Classifications, Regexs),
         is_binary(Regex)
     ]
    ].

-spec number_services_red() -> kz_term:ne_binary().
number_services_red() ->
    iolist_to_binary(
      ["function(Keys, Values, _Rereduce) {"
       "  var incr = function (o, k, v) {"
       "    o[k] = v + ((o[k] === undefined) ? 0 : o[k]);"
       "    return o;"
       "  };"
       "  var acc = function (Oout, Oin) {"
       "    for (var Ofield in Oin)"
       "      if (Oin.hasOwnProperty(Ofield))"
       "        Oout = incr(Oout, Ofield, Oin[Ofield]);"
       "    return Oout;"
       "  };"
       "  var resF = {};"
       "  var resC = {};"
       "  for (var i in Values) {"
       "    var Value = Values[i];"
       "    resF = acc(resF, Value['features'] || {});"
       "    var Classifications = Value['classifications'] || {};"
       "    for (var klass in Classifications) {"
       "      if (Classifications.hasOwnProperty(klass))"
       "        resC[klass] = acc(resC[klass] || {}, Classifications[klass]);"
       "    }"
       "  }"
       "  return {'classifications':resC, 'features':resF};"
       "}"
      ]).

-spec foreach_pause_in_between(non_neg_integer(), fun(), list()) -> 'ok'.
foreach_pause_in_between(_, _, []) -> 'ok';
foreach_pause_in_between(_, Fun, [Element]) ->
    _ = Fun(Element),
    'ok';
foreach_pause_in_between(Time, Fun, [Element|Elements]) ->
    _ = Fun(Element),
    timer:sleep(Time),
    foreach_pause_in_between(Time, Fun, Elements).

-spec pforeach(fun((A) -> any()), [A]) -> 'ok'.
pforeach(Fun, Arg1s)
  when is_function(Fun, 1),
       is_list(Arg1s) ->
    %% Malt = [%% Each worker process gets to do only 1 item before dying
    %%         1
    %%         %% A processes count of 1 is equivalent to lists:foreach-ordering
    %%         %% with each Fun being applied on its own (different) process
    %%        ,{'processes', ?PARALLEL_JOBS_COUNT}
    %%        ],
    lists:foreach(Fun, Arg1s).

-spec fix_docs(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> ok.
fix_docs(AccountDb, NumberDb, DID) ->
    Res = kz_datamgr:open_doc(AccountDb, DID),
    fix_docs(Res, AccountDb, NumberDb, DID).

fix_docs({error, timeout}, _AccountDb, _, _DID) ->
    ?SUP_LOG_DEBUG("getting ~s from ~s timed out, skipping", [_DID, _AccountDb]);
fix_docs({error, _R}, AccountDb, NumberDb, DID) ->
    ?SUP_LOG_DEBUG("failed to get ~s from ~s (~p), creating it", [DID, AccountDb, _R]),
    %% The document will be created in the next step
    Res = kz_datamgr:open_doc(NumberDb, DID),
    fix_docs(Res, kz_json:new(), AccountDb, NumberDb, DID);
fix_docs({ok, Doc}, AccountDb, NumberDb, DID) ->
    Res = kz_datamgr:open_doc(NumberDb, DID),
    fix_docs(Res, Doc, AccountDb, NumberDb, DID).

fix_docs({error, timeout}, _, _, _NumberDb, _DID) ->
    ?SUP_LOG_DEBUG("getting ~s from ~s timed out, skipping", [_DID, _NumberDb]);
fix_docs({error, _R}, Doc, AccountDb, _NumberDb, _DID) ->
    ?SUP_LOG_DEBUG("~s disappeared from ~s (~p), deleting from AccountDb", [_DID, _NumberDb]),
    case kz_datamgr:del_doc(AccountDb, Doc) of
        {ok, _} -> ok;
        {error, _R} -> ?SUP_LOG_DEBUG("sync of ~s failed: ~p", [_DID, _R])
    end;
fix_docs({ok, NumDoc}, Doc, _AccountDb, _NumberDb, DID) ->
    AccountDb = account_db_from_number_doc(NumDoc),
    ShouldEnsureDocIsInRightAccountDb = _AccountDb =/= AccountDb,
    ShouldEnsureDocIsInRightAccountDb
        andalso ?SUP_LOG_DEBUG("[~s] ~s should be in ~s instead", [_AccountDb, DID, AccountDb]),
    NewNumDoc = case kz_doc:revision(Doc) of
                    'undefined' -> kz_json:delete_keys([<<"_rev">>, <<"rev">>], NumDoc);
                    Rev -> kz_doc:set_revision(NumDoc, Rev)
                end,
    case not ShouldEnsureDocIsInRightAccountDb
        andalso NewNumDoc =:= Doc
    of
        'true' -> ?SUP_LOG_DEBUG("~s already synced", [DID]);
        'false' ->
            ?SUP_LOG_DEBUG("syncing ~s", [DID]),
            %% Replace the document within AccountDb with the doc from NumberDb.
            case kz_datamgr:save_doc(AccountDb, NewNumDoc) of
                {ok, _} ->
                    _ = kz_services:reconcile(AccountDb),
                    ok;
                {error, _R} ->
                    ?SUP_LOG_DEBUG("sync of ~s failed: ~p", [DID, _R])
            end
    end.

options() ->
    [{auth_by, ?KNM_DEFAULT_AUTH_BY}
     %% No caching + bulk doc writes
    ,{batch_run, 'true'}
    ].

account_db_from_number_doc(NumDoc) ->
    case kz_json:get_ne_binary_value(?PVT_ASSIGNED_TO, NumDoc) of
        undefined -> undefined;
        AccountId -> kz_util:format_account_db(AccountId)
    end.

-spec fix_unassign_doc(kz_term:ne_binary()) -> 'ok'.
fix_unassign_doc(DID) ->
    Setters = [{fun knm_phone_number:set_used_by/2, undefined}
              ,fun knm_phone_number:remove_denied_features/1
              ],
    case knm_number:update(DID, Setters, options()) of
        {ok, _} -> ok;
        {error, _R} -> ?SUP_LOG_DEBUG("failed fixing unassigned ~s: ~p", [DID, _R])
    end.

-type dids() :: gb_sets:set(kz_term:ne_binary()).
-spec get_DIDs(kz_term:ne_binary(), kz_term:ne_binary()) -> dids().
get_DIDs(AccountDb, View) ->
    get_DIDs(AccountDb, View, []).
-spec get_DIDs(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:proplist()) -> dids().
get_DIDs(AccountDb, View, ViewOptions) ->
    ?SUP_LOG_DEBUG("[~s] getting numbers from ~s", [AccountDb, View]),
    case kz_datamgr:get_result_keys(AccountDb, View, ViewOptions) of
        {'ok', DIDs} -> gb_sets:from_list(DIDs);
        {'error', _R} ->
            ?SUP_LOG_DEBUG("failed to get ~s DIDs from ~s: ~p", [View, AccountDb, _R]),
            gb_sets:new()
    end.

get_DIDs_callflow(AccountDb) ->
    get_DIDs_callflow(AccountDb, []).
get_DIDs_trunkstore(AccountDb) ->
    get_DIDs_trunkstore(AccountDb, []).
get_DIDs_callflow(AccountDb, ViewOptions) ->
    get_DIDs(AccountDb, <<"callflows/listing_by_number">>, ViewOptions).
get_DIDs_trunkstore(AccountDb, ViewOptions) ->
    get_DIDs(AccountDb, <<"trunkstore/lookup_did">>, ViewOptions).

-spec get_DIDs_assigned_to(kz_term:ne_binary(), kz_term:ne_binary()) -> dids().
get_DIDs_assigned_to(NumberDb, AssignedTo) ->
    ViewOptions = [{startkey, [AssignedTo]}
                  ,{endkey, [AssignedTo, kz_json:new()]}
                  ],
    case kz_datamgr:get_results(NumberDb, <<"numbers/assigned_to">>, ViewOptions) of
        {ok, JObjs} -> gb_sets:from_list([kz_doc:id(JObj) || JObj <- JObjs]);
        {error, _R} ->
            lager:debug("failed to get ~s DIDs from ~s: ~p", [AssignedTo, NumberDb, _R]),
            gb_sets:new()
    end.

-spec app_using(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:api_ne_binary().
-ifdef(TEST).
app_using(?TEST_OLD7_NUM, ?CHILD_ACCOUNT_DB) -> <<"trunkstore">>;
app_using(?NE_BINARY, ?MATCH_ACCOUNT_ENCODED(_)) -> undefined.
-else.
app_using(Num, AccountDb) ->
    app_using(Num, AccountDb, get(callflow_DIDs), get(trunkstore_DIDs)).

-type api_dids() :: undefined | dids().
-spec app_using(kz_term:ne_binary(), kz_term:ne_binary(), api_dids(), api_dids()) -> kz_term:api_ne_binary().
app_using(Num, AccountDb, undefined, TrunkstoreNums) ->
    CallflowNums = get_DIDs_callflow(AccountDb, [{key, Num}]),
    app_using(Num, AccountDb, CallflowNums, TrunkstoreNums);
app_using(Num, AccountDb, CallflowNums, undefined) ->
    TrunkstoreNums = get_DIDs_trunkstore(AccountDb, [{key, Num}]),
    app_using(Num, AccountDb, CallflowNums, TrunkstoreNums);
app_using(Num, _, CallflowNums, TrunkstoreNums) ->
    case gb_sets:is_element(Num, CallflowNums) of
        'true' -> <<"callflow">>;
        'false' ->
            case gb_sets:is_element(Num, TrunkstoreNums) of
                'true' -> <<"trunkstore">>;
                'false' -> undefined
            end
    end.
-endif.

-spec is_assigned_to(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_assigned_to(AccountDb, DID, AccountId) ->
    case kz_datamgr:open_doc(AccountDb, DID) of
        {error, _R} ->
            lager:debug("~s's ~s temporarily unavailable, skipping", [AccountDb, DID]),
            'true';
        {ok, Doc} ->
            AccountId =/= kz_json:get_ne_binary_value(?PVT_ASSIGNED_TO, Doc)
    end.


-spec generate_numbers(kz_term:ne_binary(), kz_term:ne_binary(), pos_integer(), non_neg_integer()) -> 'ok'.
generate_numbers(Type, AccountId, StartingNumber, Quantity) ->
    M = kz_term:to_atom(<<"knm_", Type/binary>>, 'true'),
    M:generate_numbers(AccountId, kz_term:to_integer(StartingNumber), kz_term:to_integer(Quantity)).


-spec delete(kz_term:ne_binary()) -> 'no_return'.
delete(Num) ->
    case knm_number:delete(Num, knm_number_options:default()) of
        {'ok', _} -> io:format("Removed ~s\n", [Num]);
        {'error', _R} -> io:format("ERROR: ~p\n", [_R])
    end,
    'no_return'.


-spec purge_discovery() -> 'no_return'.
purge_discovery() ->
    Purge = fun (NumberDb) -> purge_number_db(NumberDb, ?NUMBER_STATE_DISCOVERY) end,
    pforeach(Purge, knm_util:get_all_number_dbs()),
    'no_return'.

-spec purge_deleted(kz_term:ne_binary()) -> 'no_return'.
purge_deleted(Prefix) ->
    purge_number_db(<<?KNM_DB_PREFIX_ENCODED, Prefix/binary>>, ?NUMBER_STATE_DELETED),
    'no_return'.

-spec purge_deleted() -> 'no_return'.
purge_deleted() ->
    Purge = fun (NumberDb) -> purge_number_db(NumberDb, ?NUMBER_STATE_DELETED) end,
    pforeach(Purge, knm_util:get_all_number_dbs()),
    'no_return'.

-spec purge_discovery(kz_term:ne_binary()) -> 'no_return'.
purge_discovery(Prefix) ->
    purge_number_db(<<?KNM_DB_PREFIX_ENCODED, Prefix/binary>>, ?NUMBER_STATE_DISCOVERY),
    'no_return'.

-spec purge_number_db(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
purge_number_db(NumberDb, State) ->
    ViewOptions = [{'startkey', [State]}
                  ,{'endkey', [State, kz_json:new()]}
                  ,'include_docs'
                  ,{'limit', 500}
                  ],
    case kz_datamgr:get_results(NumberDb, <<"numbers/status">>, ViewOptions) of
        {'ok', []} -> 'ok';
        {'ok', Numbers} ->
            io:format("removing ~p numbers in state '~s' from ~s~n", [length(Numbers), State, NumberDb]),
            JObjs = [JObj || Number <- Numbers,
                             JObj <- [kz_json:get_value(<<"doc">>, Number)],
                             State =:= kz_json:get_value(?PVT_STATE, JObj)
                    ],
            _ = kz_datamgr:del_docs(NumberDb, JObjs),
            purge_number_db(NumberDb, State)
    end.

-spec is_feature_valid(any()) -> boolean().
is_feature_valid(Thing) ->
    lists:member(Thing, ?ALL_KNM_FEATURES).

-spec invalid_feature(kz_term:ne_binary()) -> 'no_return'.
invalid_feature(Feature) ->
    io:format("Feature '~s' is not a known feature.\n", [Feature]),
    all_features().

-spec all_features() -> 'no_return'.
all_features() ->
    io:format("Known features:\n\t~s\n", [list_features(?ALL_KNM_FEATURES)]),
    'no_return'.

-spec list_features(kz_term:ne_binaries()) -> iodata().
list_features(Features) ->
    kz_util:iolist_join($\s, Features).

-spec error_with_number(kz_term:ne_binary(), any()) -> 'no_return'.
error_with_number(Num, Error) ->
    Reason = case kz_json:is_json_object(Error) of
                 'false' -> Error;
                 'true' -> knm_errors:error(Error)
             end,
    io:format("Error with number ~s: ~s\n", [Num, Reason]),
    'no_return'.

-spec print_feature_permissions(kz_term:ne_binaries(), kz_term:ne_binaries()) -> 'no_return'.
print_feature_permissions(Allowed, Denied) ->
    io:format("\tFeatures allowed: ~s\n"
              "\tFeatures denied: ~s\n"
             ,[list_features(Allowed), list_features(Denied)]
             ),
    'no_return'.

-spec list_number_feature_permissions(knm_number:knm_number()) -> 'no_return'.
list_number_feature_permissions(N) ->
    PN = knm_number:phone_number(N),
    Num = knm_phone_number:number(PN),
    Allowed = knm_phone_number:features_allowed(PN),
    Denied = knm_phone_number:features_denied(PN),
    io:format("Feature permissions on ~s:\n", [Num]),
    print_feature_permissions(Allowed, Denied).

-spec edit_feature_permissions_on_number(kz_term:ne_binary(), fun(), kz_term:ne_binary()) -> 'no_return'.
edit_feature_permissions_on_number(Num, Fun, Feature) ->
    case is_feature_valid(Feature) of
        'false' -> invalid_feature(Feature);
        'true' ->
            Updates = [{Fun, Feature}],
            case knm_number:update(Num, Updates) of
                {'ok', N} -> list_number_feature_permissions(N);
                {'error', Error} -> error_with_number(Num, Error)
            end
    end.

-spec feature_permissions_on_number(kz_term:ne_binary()) -> 'no_return'.
feature_permissions_on_number(Num) ->
    case knm_number:get(Num) of
        {'error', Error} -> error_with_number(Num, Error);
        {'ok', N} -> list_number_feature_permissions(N)
    end.

-spec add_allowed_feature_on_number(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
add_allowed_feature_on_number(?NE_BINARY=Feature, ?NE_BINARY=Num) ->
    edit_feature_permissions_on_number(Num, fun knm_phone_number:add_allowed_feature/2, Feature).

-spec remove_allowed_feature_on_number(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
remove_allowed_feature_on_number(?NE_BINARY=Feature, ?NE_BINARY=Num) ->
    edit_feature_permissions_on_number(Num, fun knm_phone_number:remove_allowed_feature/2, Feature).

-spec add_denied_feature_on_number(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
add_denied_feature_on_number(?NE_BINARY=Feature, ?NE_BINARY=Num) ->
    edit_feature_permissions_on_number(Num, fun knm_phone_number:add_denied_feature/2, Feature).

-spec remove_denied_feature_on_number(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
remove_denied_feature_on_number(?NE_BINARY=Feature, ?NE_BINARY=Num) ->
    edit_feature_permissions_on_number(Num, fun knm_phone_number:remove_denied_feature/2, Feature).

-spec feature_permissions_on_reseller_of(kz_term:ne_binary()) -> 'no_return'.
feature_permissions_on_reseller_of(?MATCH_ACCOUNT_RAW(AccountId)) ->
    Allowed = empty_list_when_undefined(?FEATURES_ALLOWED_RESELLER(AccountId)),
    Denied = empty_list_when_undefined(?FEATURES_DENIED_RESELLER(AccountId)),
    ResellerId = kz_services_reseller:get_id(AccountId),
    io:format("Feature permissions on reseller of ~s (~s):\n", [AccountId, ResellerId]),
    print_feature_permissions(Allowed, Denied).

-spec empty_list_when_undefined(kz_term:api_list()) -> kz_term:ne_binaries().
empty_list_when_undefined('undefined') -> [];
empty_list_when_undefined(NeBinaries) -> NeBinaries.

-spec edit_allowed_feature_permissions_on_reseller_of(kz_term:ne_binary(), fun(), kz_term:ne_binary()) -> 'no_return'.
edit_allowed_feature_permissions_on_reseller_of(AccountId, Fun, Feature) ->
    case is_feature_valid(Feature) of
        'false' -> invalid_feature(Feature);
        'true' ->
            Allowed = empty_list_when_undefined(?FEATURES_ALLOWED_RESELLER(AccountId)),
            NewFeatures = lists:usort(Fun(Feature, Allowed)),
            ResellerId = kz_services_reseller:get_id(AccountId),
            _ = kapps_account_config:set(ResellerId, ?KNM_CONFIG_CAT, ?KEY_FEATURES_ALLOW, NewFeatures),
            feature_permissions_on_reseller_of(AccountId)
    end.

-spec edit_denied_feature_permissions_on_reseller_of(kz_term:ne_binary(), fun(), kz_term:ne_binary()) -> 'no_return'.
edit_denied_feature_permissions_on_reseller_of(AccountId, Fun, Feature) ->
    case is_feature_valid(Feature) of
        'false' -> invalid_feature(Feature);
        'true' ->
            Denied = empty_list_when_undefined(?FEATURES_DENIED_RESELLER(AccountId)),
            NewFeatures = lists:usort(Fun(Feature, Denied)),
            ResellerId = kz_services_reseller:get_id(AccountId),
            _ = kapps_account_config:set(ResellerId, ?KNM_CONFIG_CAT, ?KEY_FEATURES_DENY, NewFeatures),
            feature_permissions_on_reseller_of(AccountId)
    end.

-spec add_allowed_feature_on_reseller_of(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
add_allowed_feature_on_reseller_of(?NE_BINARY=Feature, ?MATCH_ACCOUNT_RAW(AccountId)) ->
    Cons = fun (AFeature, Features) -> [AFeature|Features] end,
    edit_allowed_feature_permissions_on_reseller_of(AccountId, Cons, Feature).

-spec remove_allowed_feature_on_reseller_of(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
remove_allowed_feature_on_reseller_of(?NE_BINARY=Feature, ?MATCH_ACCOUNT_RAW(AccountId)) ->
    edit_allowed_feature_permissions_on_reseller_of(AccountId, fun lists:delete/2, Feature).

-spec add_denied_feature_on_reseller_of(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
add_denied_feature_on_reseller_of(?NE_BINARY=Feature, ?MATCH_ACCOUNT_RAW(AccountId)) ->
    Cons = fun (AFeature, Features) -> [AFeature|Features] end,
    edit_denied_feature_permissions_on_reseller_of(AccountId, Cons, Feature).

-spec remove_denied_feature_on_reseller_of(kz_term:ne_binary(), kz_term:ne_binary()) -> 'no_return'.
remove_denied_feature_on_reseller_of(?NE_BINARY=Feature, ?MATCH_ACCOUNT_RAW(AccountId)) ->
    edit_denied_feature_permissions_on_reseller_of(AccountId, fun lists:delete/2, Feature).

-spec feature_permissions_on_system_config() -> 'no_return'.
feature_permissions_on_system_config() ->
    Allowed = knm_providers:system_allowed_features(),
    io:format("Features allowed on system config document:\n\t~s\n", [list_features(Allowed)]),
    'no_return'.

-spec reset_allowed_features_to_defaults_on_system_config() -> 'no_return'.
reset_allowed_features_to_defaults_on_system_config() ->
    set_features_on_system_config(?DEFAULT_FEATURES_ALLOWED_SYSTEM).

-spec set_features_on_system_config(kz_term:ne_binaries()) -> 'no_return'.
set_features_on_system_config(Features) ->
    _ = kapps_config:set(?KNM_CONFIG_CAT, ?KEY_FEATURES_ALLOW, lists:usort(Features)),
    feature_permissions_on_system_config().

-spec edit_allowed_feature_permissions_on_system_config(fun(), kz_term:ne_binary()) -> 'no_return'.
edit_allowed_feature_permissions_on_system_config(Fun, Feature) ->
    case is_feature_valid(Feature) of
        'false' -> invalid_feature(Feature);
        'true' ->
            Allowed = knm_providers:system_allowed_features(),
            set_features_on_system_config(Fun(Feature, Allowed))
    end.

-spec add_allowed_feature_on_system_config(kz_term:ne_binary()) -> 'no_return'.
add_allowed_feature_on_system_config(?NE_BINARY=Feature) ->
    Cons = fun (AFeature, Features) -> [AFeature|Features] end,
    edit_allowed_feature_permissions_on_system_config(Cons, Feature).

-spec remove_allowed_feature_on_system_config(kz_term:ne_binary()) -> 'no_return'.
remove_allowed_feature_on_system_config(?NE_BINARY=Feature) ->
    edit_allowed_feature_permissions_on_system_config(fun lists:delete/2, Feature).

-spec ensure_adminonly_features_are_reachable() -> 'no_return'.
ensure_adminonly_features_are_reachable() ->
    Configured = knm_providers:system_allowed_features(),
    case lists:usort(?ADMIN_ONLY_FEATURES) -- Configured of
        [] -> 'no_return';
        ToAdd ->
            io:format("Adding the following admin-only number features to system_config: ~s"
                     ,[list_features(ToAdd)]),
            set_features_on_system_config(ToAdd ++ Configured)
    end.

-spec migrate_port_requests() -> 'ok'.
migrate_port_requests() ->
    knm_port_request:migrate().
