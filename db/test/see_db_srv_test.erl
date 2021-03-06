-module(see_db_srv_test).
-include_lib("eunit/include/eunit.hrl").

-define(URL, "http://www.foo.com/").
-define(WORDS, <<"aaa ddd eee fff">>).

-define(URL2, "url2").
-define(WORDS2, <<"bbb ddd eee ggg">>).

-define(URL3, "url3").
-define(WORDS3, <<"ccc ddd fff ggg">>).

-define(assert_search_result(URLs, Phrase),
        ?_assertEqual(lists:sort(URLs), lists:sort(see_db_srv:search(Phrase)))).

start() ->
    meck:new(see_text),
    meck:expect(see_text, extract_words, fun(X) -> binary:split(X, <<" ">>, [global, trim_all]) end),
    {ok, Pid} = see_db_srv:start(),
    ?assert(is_pid(Pid)),
    Pid.

stop(_) ->
    ?assert(meck:validate(see_text)),
    meck:unload(see_text),
    see_db_srv:stop().

queued_page() ->
    Pid = start(),
    ok = see_db_srv:queue(?URL),
    Pid.

visited_page() ->
    Pid = start(),
    see_db_srv:visited(?URL, {data, ?WORDS}),
    Pid.

visited_many_pages() ->
    Pid = start(),
    see_db_srv:visited(?URL, {data, ?WORDS}),
    see_db_srv:visited(?URL2, {data, ?WORDS2}),
    see_db_srv:visited(?URL3, {data, ?WORDS3}),
    Pid.

visited_many_same_pages() ->
    Pid = start(),
    see_db_srv:visited(?URL, {data, ?WORDS}),
    see_db_srv:visited(?URL2, {data, ?WORDS}),
    see_db_srv:visited(?URL3, {data, ?WORDS}),
    Pid.

visited_page_has_changed() ->
    Pid = start(),
    see_db_srv:visited(?URL, {data, ?WORDS}),
    see_db_srv:visited(?URL, {data, ?WORDS2}),
    Pid.

when_no_queued_urls__next_returns_nothing_test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             ?_assertEqual(nothing, see_db_srv:next())
     end}.

when_queued_url__next_returns_it_test_() ->
    {setup, fun queued_page/0, fun stop/1,
     fun(_) ->
             [?_assertEqual({ok, ?URL}, see_db_srv:next()),
              ?_assertEqual({ok, ?URL}, see_db_srv:next())]
     end}.

when_url_is_invalid__queue_returns_error_test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             ?_assertEqual(error, see_db_srv:queue("www.wrong.url"))
     end}.

when_queued_url_with_no_path__root_path_is_added__test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             URL = "http://www.url.com",
             [?_assertEqual(ok, see_db_srv:queue(URL)),
              ?_assertEqual({ok, URL ++ "/"}, see_db_srv:next())]
     end}.

when_queued_url_with_fragment__fragment_is_discared__test_() ->
    {setup, fun start/0, fun stop/1,
     fun(_) ->
             URL = "http://www.url.com/foo?query",
             [?_assertEqual(ok, see_db_srv:queue(URL ++ "#fragment")),
              ?_assertEqual({ok, URL}, see_db_srv:next())]
     end}.

when_all_pages_visited__next_returns_nothing_test_() ->
    {foreach, fun queued_page/0, fun stop/1,
     [fun(_) ->
              see_db_srv:visited(?URL, {data, ?WORDS}),
              ?_assertEqual(nothing, see_db_srv:next())
      end,
      fun(_) ->
              see_db_srv:visited(?URL, {redirect, "redirect url"}),
              ?_assertEqual(nothing, see_db_srv:next())
      end,
      fun(_) ->
              see_db_srv:visited(?URL, binary),
              ?_assertEqual(nothing, see_db_srv:next())
      end]}.

when_page_is_visited__it_cannot_be_queued_again_test_() ->
    {setup, fun visited_page/0, fun stop/1,
     fun(_) ->
             [?_assertMatch(ok, see_db_srv:queue(?URL)),
              ?_assertEqual(nothing, see_db_srv:next())]
     end}.

when_phrase_is_empty__search_returns_empty_list_test_() ->
    {setup, fun visited_page/0, fun stop/1,
     fun(_) ->
             ?assert_search_result([], <<"">>)
     end}.

when_word_is_not_present__search_returns_empty_list_test_() ->
    {setup, fun visited_page/0, fun stop/1,
     fun(_) ->
             ?assert_search_result([], <<"dfsd">>)
     end}.

when_word_is_present_on_one_page__search_returns_single_page_list_test_() ->
    {setup, fun visited_page/0, fun stop/1,
     fun(_) ->
             [?assert_search_result([?URL], Word) || Word <- binary:split(?WORDS, <<" ">>, [global])]
     end}.

when_phrase_is_present_on_one_page__search_returns_single_page_list_test_() ->
    {setup, fun visited_many_pages/0, fun stop/1,
     fun(_) ->
             [?assert_search_result([?URL],  ?WORDS),
              ?assert_search_result([?URL2], ?WORDS2),
              ?assert_search_result([?URL3], ?WORDS3)]
     end}.

when_word_is_present_on_many_pages__search_returns_them_all_test_() ->
    {setup, fun visited_many_pages/0, fun stop/1,
     fun(_) ->
             [?assert_search_result([?URL], <<"aaa">>),
              ?assert_search_result([?URL2], <<"bbb">>),
              ?assert_search_result([?URL3], <<"ccc">>),
              ?assert_search_result([?URL, ?URL2], <<"eee">>),
              ?assert_search_result([?URL, ?URL3], <<"fff">>),
              ?assert_search_result([?URL2, ?URL3], <<"ggg">>),
              ?assert_search_result([?URL, ?URL2, ?URL3], <<"ddd">>)]
     end}.

when_many_words_are_given__search_returns_pages_containing_all_of_them_test_() ->
    {setup, fun visited_many_same_pages/0, fun stop/1,
     fun(_) ->
              [?assert_search_result([?URL, ?URL2, ?URL3], <<"aaa ddd">>),
               ?assert_search_result([?URL, ?URL2, ?URL3], <<"aaa ddd eee">>),
               ?assert_search_result([?URL, ?URL2, ?URL3], <<"aaa ddd eee fff">>),
               ?assert_search_result([], <<"aaa bbb">>)]
     end}.

when_page_changes__search_returns_only_new_content_test_() ->
    {setup, fun visited_page_has_changed/0, fun stop/1,
     fun(_) ->
              [?assert_search_result([], <<"aaa">>),
               ?assert_search_result([?URL], <<"ddd">>),
               ?assert_search_result([?URL], <<"ggg">>)]
     end}.
