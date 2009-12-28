%%% @author     Roberto Saccon <rsaccon@gmail.com> [http://rsaccon.com]
%%% @author     Stuart Jackson <simpleenigmainc@gmail.com> [http://erlsoft.org]
%%% @author     Luke Hubbard <luke@codegent.com> [http://www.codegent.com]
%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2007 Luke Hubbard, Stuart Jackson, Roberto Saccon, 2009 Max Lapshin
%%% @doc        RTMP encoding/decoding module. 
%%% @reference  See <a href="http://erlyvideo.org/rtmp" target="_top">http://erlyvideo.org/rtmp</a> for more information.
%%% @end
%%%
%%%
%%% The MIT License
%%%
%%% Copyright (c) 2007 Luke Hubbard, Stuart Jackson, Roberto Saccon, 2009 Max Lapshin
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in
%%% all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%%% THE SOFTWARE.
%%%
%%%---------------------------------------------------------------------------------------
-module(rtmp).
-author('rsaccon@gmail.com').
-author('simpleenigmainc@gmail.com').
-author('luke@codegent.com').
-author('max@maxidoors.ru').
-include("../include/rtmp.hrl").
-include("../include/rtmp_private.hrl").

-export([encode/2, decode/2]).

%%--------------------------------------------------------------------
%% @spec (Socket::rtmp_socket(), Message::rtmp_message()) -> {NewSocket::rtmp_socket(), Packet::binary()}
%% @doc Encodes outgoing message to chunked binary packet, prepared to be written
%% to TCP socket. As RTMP is a stateful protocol, state is modified on each encode.
%% Things, that change in state are chunk size and "last" stream_id, timestamp, packet length.
%% Thus, two sequential calls to encode can give you different results:
%% 
%% <code>{NewSocket, Packet} = encode(Socket, #rtmp_message{type = chunk_size, body = 10}),<br/>
%% {NewSocket1, Packet1} = encode(NewSocket, #rtmp_message{type = chunk_size, body = 10}).</code><br/>
%% First message will be chunked sent with default chunk size 128, but second will use chunk size 10
%% and will differ from previous one.
%%
%% You can ask, where can you take Socket to use this module? Currently there are no methods to
%% construct it from nowhere, because RTMP protocol is useless without other connected side,
%% so take a use of {@link rtmp_socket. rtmp_socket} module, that instantiates Socket for you.
%%
%% To read description about rtmp_message, look for {@link decode/2. decode/2} documentation.
%% @end 
%%--------------------------------------------------------------------

encode(State, #rtmp_message{timestamp = undefined} = Message) -> 
  encode(State, Message#rtmp_message{timestamp = 0});

encode(State, #rtmp_message{stream_id = undefined} = Message) -> 
  encode(State, Message#rtmp_message{stream_id = 0});

encode(State, #rtmp_message{channel_id = undefined, type = invoke} = Message)  -> 
  encode(State, Message#rtmp_message{channel_id = 3});

encode(State, #rtmp_message{channel_id = undefined} = Message)  -> 
  encode(State, Message#rtmp_message{channel_id = 2});

encode(State, #rtmp_message{type = chunk_size, body = ChunkSize} = Message) ->
  encode(State#rtmp_socket{server_chunk_size = ChunkSize}, Message#rtmp_message{type = ?RTMP_TYPE_CHUNK_SIZE, body = <<ChunkSize:32/big-integer>>});

encode(#rtmp_socket{bytes_read = BytesRead} = State, #rtmp_message{type = ack_read} = Message) ->
  encode(State#rtmp_socket{bytes_read = 0}, Message#rtmp_message{type = ?RTMP_TYPE_ACK_READ, body = <<BytesRead:32/big-integer>>});

encode(State, #rtmp_message{type = stream_begin} = Message) ->
  encode(State, Message#rtmp_message{type = control, body = ?RTMP_CONTROL_STREAM_BEGIN});

encode(State, #rtmp_message{type = stream_end} = Message) ->
  encode(State, Message#rtmp_message{type = control, body = ?RTMP_CONTROL_STREAM_EOF});

encode(State, #rtmp_message{type = stream_recorded} = Message) ->
  encode(State, Message#rtmp_message{type = control, body = ?RTMP_CONTROL_STREAM_RECORDED});

encode(State, #rtmp_message{type = ping} = Message) ->
  encode(State, Message#rtmp_message{type = control, body = ?RTMP_CONTROL_STREAM_PING});

encode(State, #rtmp_message{type = pong} = Message) ->
  encode(State, Message#rtmp_message{type = control, body = ?RTMP_CONTROL_STREAM_PONG});
  
encode(State, #rtmp_message{type = control, body = EventType, stream_id = StreamId} = Message) ->
  encode(State, Message#rtmp_message{type = ?RTMP_TYPE_CONTROL, body = <<EventType:16, StreamId:32>>});

encode(State, #rtmp_message{type = window_size, body = WindowAckSize} = Message) ->
  encode(State#rtmp_socket{previous_ack = erlang:now()}, Message#rtmp_message{type = ?RTMP_TYPE_WINDOW_ACK_SIZE, body = <<WindowAckSize:32>>});

encode(State, #rtmp_message{type = bw_peer, body = WindowAckSize} = Message) ->
  encode(State, Message#rtmp_message{type = ?RTMP_TYPE_BW_PEER, body = <<WindowAckSize:32, 16#02>>});

encode(State, #rtmp_message{type = audio} = Message) ->
  encode(State, Message#rtmp_message{type = ?RTMP_TYPE_AUDIO});

encode(State, #rtmp_message{type = video} = Message) ->
  encode(State, Message#rtmp_message{type = ?RTMP_TYPE_VIDEO});

encode(#rtmp_socket{amf_version = 0} = State, #rtmp_message{type = invoke, body = AMF} = Message) when is_record(AMF, rtmp_funcall)-> 
	encode(State, Message#rtmp_message{body = encode_funcall(AMF), type = ?RTMP_INVOKE_AMF0});

encode(#rtmp_socket{amf_version = 3} = State, #rtmp_message{type = invoke, body = AMF} = Message) when is_record(AMF, rtmp_funcall)-> 
	encode(State, Message#rtmp_message{body = <<0, (encode_funcall(AMF))/binary>>, type = ?RTMP_INVOKE_AMF3});

encode(#rtmp_socket{amf_version = 0} = State, #rtmp_message{type = metadata, body = Body} = Message) when is_binary(Body) -> 
	encode(State, Message#rtmp_message{body = Body, type = ?RTMP_TYPE_METADATA_AMF0});

encode(#rtmp_socket{amf_version = 3} = State, #rtmp_message{type = metadata, body = Body} = Message) when is_binary(Body)-> 
	encode(State, Message#rtmp_message{body = Body, type = ?RTMP_TYPE_METADATA_AMF3});

encode(#rtmp_socket{amf_version = 0} = State, #rtmp_message{type = metadata, body = Object} = Message) -> 
	encode(State, Message#rtmp_message{body = amf0:encode(Object), type = ?RTMP_TYPE_METADATA_AMF0});

encode(#rtmp_socket{amf_version = 3} = State, #rtmp_message{type = metadata, body = Object} = Message) -> 
	encode(State, Message#rtmp_message{body = amf0:encode(Object), type = ?RTMP_TYPE_METADATA_AMF3});

encode(#rtmp_socket{amf_version = 0} = State, #rtmp_message{type = shared_object, body = SOMessage} = Message) when is_record(SOMessage, so_message)->
  encode(State, Message#rtmp_message{body = encode_shared_object(SOMessage), type = ?RTMP_TYPE_SO_AMF0});

encode(#rtmp_socket{amf_version = 3} = State, #rtmp_message{type = shared_object, body = SOMessage} = Message) when is_record(SOMessage, so_message)->
  encode(State, Message#rtmp_message{body = encode_shared_object(SOMessage), type = ?RTMP_TYPE_SO_AMF3});

encode(State, #rtmp_message{timestamp = TimeStamp} = Message) when is_float(TimeStamp) -> 
  encode(State, Message#rtmp_message{timestamp = round(TimeStamp)});

encode(State, #rtmp_message{stream_id = StreamId} = Message) when is_float(StreamId) -> 
  encode(State, Message#rtmp_message{stream_id = round(StreamId)});

encode(#rtmp_socket{server_chunk_size = ChunkSize} = State, 
       #rtmp_message{channel_id = Id, timestamp = Timestamp, type = Type, stream_id = StreamId, body = Data}) when is_binary(Data) and is_integer(Type)-> 
  ChunkList = chunk(Data, ChunkSize, Id),
	BinId = encode_id(?RTMP_HDR_NEW,Id),
  {State, [<<BinId/binary,Timestamp:24,(size(Data)):24,Type:8,StreamId:32/little>> | ChunkList]}.

encode_funcall(#rtmp_funcall{command = Command, args = Args, id = Id, type = invoke}) -> 
  <<(amf0:encode(atom_to_binary(Command, utf8)))/binary, (amf0:encode(Id))/binary, 
    (encode_list(<<>>, Args))/binary>>;
 
encode_funcall(#rtmp_funcall{command = Command, args = Args, type = notify}) -> 
<<(amf0:encode(atom_to_binary(Command, utf8)))/binary,
  (encode_list(<<>>, Args))/binary>>.

encode_list(Message, []) -> Message;
encode_list(Message, [Arg | Args]) ->
  AMF = amf0:encode(Arg),
  encode_list(<<Message/binary, AMF/binary>>, Args).

encode_id(Type, Id) when Id > 319 -> 
	<<Type:2,?RTMP_HDR_LRG_ID:6, (Id - 64):16/big-integer>>;
encode_id(Type, Id) when Id > 63 -> 
	<<Type:2,?RTMP_HDR_MED_ID:6, (Id - 64):8>>;
encode_id(Type, Id) when Id >= 2 -> 
  <<Type:2, Id:6>>.


% chunk(Data) -> chunk(Data,?RTMP_DEF_CHUNK_SIZE).

chunk(Data, ChunkSize, Id) -> chunk(Data, ChunkSize, Id, []).

chunk(Data, ChunkSize, _Id, List) when size(Data) =< ChunkSize ->
  lists:reverse([Data | List]);


chunk(Data, ChunkSize, Id, List) when is_binary(Data) ->
  <<Chunk:ChunkSize/binary,Rest/binary>> = Data,
  chunk(Rest, ChunkSize, Id, [encode_id(?RTMP_HDR_CONTINUE, Id), Chunk | List]).
		
		
		
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DECODING %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%		
		
		
%%--------------------------------------------------------------------
%% @spec (Socket::rtmp_socket(), Packet::binary()) -> {NewSocket::rtmp_socket(), Message::rtmp_message(), Rest::binary()} | {NewSocket::rtmp_socket, Rest::binary()}
%% @doc Encodes outgoing message to chunked binary packet, prepared to be written
%% to TCP socket.
%% 
%% RTMP is stateful protocol, so incoming messages modify state of protocol decoder. You need to keep
%% track of it. {@link rtmp_socket. rtmp_socket} module can do this for you.
%% 
%% If it is enough data received, decode will return rtmp_message() and unconsumed bytes, that you need to store somewhere
%% in buffer and pass them next time, when you get more bytes. Even in this case you need to keep new state, 
%% because rtmp_socket() has its own internal buffers, that are filled. It is required for chunks of packets.
%%
%% So, always keep new state and keep returned buffer somewhere.
%%
%% rtmp_message has following (interesting for you) structure:
%% <ul>
%% <li><code>timestamp</code> this field is interesting only for audio/video messages</li>
%% <li><code>type</code> you can read different types further</li>
%% <li><code>stream_id</code> this field is default 0 (message received not on NetStream object, but on NetConnection)</li>
%% <li><code>body</code> this field is correlated with type, read further.</li>
%% </ul>
%%
%% Here goes list of possible messages, you can receive from RTMP stream:
%% <ol>
%% <li><code>#rtmp_message{type=window_size, body=WindowSize}</code> other side wants you to send ack_read message once in <code>WindowSize</code> bytes</li>
%% <li><code>#rtmp_message{type=stream_begin, stream_id=StreamId}</code> audio/video is starting on stream StreamId</li>
%% <li><code>#rtmp_message{type=stream_end, stream_id=StreamId}</code> audio/video is finished on stream StreamId</li>
%% <li><code>#rtmp_message{type=buffer_size, body=BufferSize, stream_id=StreamId}</code> other side tells us, that it has BufferSize a/v buffer on stream StreamId</li>
%% <li><code>#rtmp_message{type=stream_recorded, stream_id=StreamId}</code> stream StreamId was recorded on disc before sending to us</li>
%% <li><code>#rtmp_message{type=ping, body=Timestamp}</code> at time Timestamp peer sent us ping, we should reply with pong</li>
%% <li><code>#rtmp_message{type=control, body={EventType, Data}, stream_id=StreamId}</code> some other undecoded control message received</li>
%% <li><code>#rtmp_message{type=broken_meta, stream_id=StreamId}</code> audio/video with null size received. It happens sometimes, never mind and ignore.</li>
%% <li><code>#rtmp_message{type=audio, body=Body, stream_id=StreamId}</code> audio packet received on StreamId</li>
%% <li><code>#rtmp_message{type=video, body=Body, stream_id=StreamId}</code> video packet received on StreamId</li>
%% <li><code>#rtmp_message{type=metadata, body=Body, stream_id=StreamId}</code> metadata packet received on StreamId. It is usually sent, when flash client starts recording video stream from camera and tells size of video.</li>
%% <li><code>#rtmp_message{type=invoke, body=Funcall::rtmp_funcall()}</code> function is invoked. Read further about Funcall object.</li>
%% <li><code>#rtmp_message{type=shared_object, body=SharedObjectMessage}</code> shared object event happened. Not implemented yet.</li>
%% </ol>
%% @end 
%%--------------------------------------------------------------------
decode(#rtmp_socket{} = State, <<>>) -> {State, <<>>};
decode(#rtmp_socket{} = State, Data) when is_binary(Data) -> 
  case decode_channel_id(Data, State) of
    {NewState, Message, Rest} -> {NewState, Message, Rest};
    {NewState, Rest} -> {NewState, Rest};
    NewState -> {NewState, Data}
  end.

% First extracting channel id
decode_channel_id(<<Format:2, ?RTMP_HDR_LRG_ID:6,Id:16, Rest/binary>>, State) ->
  decode_channel_header(Rest, Format, Id + 64, State);
decode_channel_id(<<Format:2, ?RTMP_HDR_MED_ID:6,Id:8, Rest/binary>>, State) ->
  decode_channel_header(Rest, Format, Id + 64, State);
decode_channel_id(<<Format:2, Id:6, Rest/binary>>, State) ->
  decode_channel_header(Rest, Format, Id, State).

% Now extracting channel header
decode_channel_header(Rest, ?RTMP_HDR_CONTINUE, Id, State) ->
  Channel = array:get(Id, State#rtmp_socket.channels),
  #channel{msg = Msg, timestamp = Timestamp, delta = Delta} = Channel,
  Channel1 = case {Delta, size(Msg)} of
    {undefined, _} -> Channel;
    {_, 0} -> Channel#channel{timestamp = Timestamp + Delta};
    _ -> Channel
  end,
  decode_channel(Rest,Channel1,State);

decode_channel_header(<<16#ffffff:24, TimeStamp:32, Rest/binary>>, ?RTMP_HDR_TS_CHG, Id, State) ->
  Channel = array:get(Id, State#rtmp_socket.channels),
  decode_channel(Rest,Channel#channel{timestamp = TimeStamp+16#ffffff, delta = undefined},State);
  
decode_channel_header(<<Delta:24, Rest/binary>>, ?RTMP_HDR_TS_CHG, Id, State) ->
  Channel = array:get(Id, State#rtmp_socket.channels),
  #channel{timestamp = TimeStamp} = Channel,
  decode_channel(Rest, Channel#channel{timestamp = TimeStamp + Delta, delta = Delta},State);
  
decode_channel_header(<<16#ffffff:24,Length:24,Type:8,TimeStamp:32,Rest/binary>>, ?RTMP_HDR_SAME_SRC, Id, State) ->
  Channel = array:get(Id, State#rtmp_socket.channels),
	decode_channel(Rest,Channel#channel{timestamp=TimeStamp+16#ffffff, delta = undefined, length=Length,type=Type},State);
	
decode_channel_header(<<Delta:24,Length:24,Type:8,Rest/binary>>, ?RTMP_HDR_SAME_SRC, Id, State) ->
  Channel = array:get(Id, State#rtmp_socket.channels),
  #channel{timestamp = TimeStamp} = Channel,
	decode_channel(Rest,Channel#channel{timestamp=TimeStamp + Delta, delta = Delta, length=Length,type=Type},State);

decode_channel_header(<<16#ffffff:24,Length:24,Type:8,StreamId:32/little,TimeStamp:32,Rest/binary>>,?RTMP_HDR_NEW,Id, 
  #rtmp_socket{channels = Channels} = State) when size(Channels) < Id ->
  decode_channel(Rest,#channel{id=Id,timestamp=TimeStamp+16#ffffff,delta = undefined, length=Length,type=Type,stream_id=StreamId},State);

decode_channel_header(<<16#ffffff:24,Length:24,Type:8,StreamId:32/little,TimeStamp:32,Rest/binary>>,?RTMP_HDR_NEW,Id, State) ->
  case array:get(Id, State#rtmp_socket.channels) of
    #channel{} = Channel -> ok;
    _ -> Channel = #channel{}
  end,
	decode_channel(Rest,Channel#channel{id=Id,timestamp=TimeStamp+16#ffffff,delta = undefined, length=Length,type=Type,stream_id=StreamId},State);
	
decode_channel_header(<<TimeStamp:24,Length:24,Type:8,StreamId:32/little,Rest/binary>>,?RTMP_HDR_NEW,Id, State) ->
  case array:get(Id, State#rtmp_socket.channels) of
    #channel{} = Channel -> ok;
    _ -> Channel = #channel{}
  end,
	decode_channel(Rest,Channel#channel{id=Id,timestamp=TimeStamp,delta = undefined, length=Length,type=Type,stream_id=StreamId},State);

decode_channel_header(_Rest,_Type, _Id,  State) -> % Still small buffer
  State.

% Now trying to fill channel with required data
bytes_for_channel(#channel{length = Length, msg = Msg}, _) when size(Msg) == Length ->
  0;

bytes_for_channel(#channel{length = Length, msg = Msg}, #rtmp_socket{client_chunk_size = ChunkSize}) when Length - size(Msg) < ChunkSize ->
  Length - size(Msg);
  
bytes_for_channel(_, #rtmp_socket{client_chunk_size = ChunkSize}) -> ChunkSize.
  

decode_channel(Data, Channel, State) ->
	BytesRequired = bytes_for_channel(Channel, State),
	push_channel_packet(Data, Channel, State, BytesRequired).
	
% Nothing to do when buffer is small

push_channel_packet(Data, _Channel, State, BytesRequired) when size(Data) < BytesRequired ->
  State;
  
% And decode channel when bytes required are in buffer
push_channel_packet(Data, #channel{msg = Msg} = Channel, State, BytesRequired) -> 
  <<Chunk:BytesRequired/binary, Rest/binary>> = Data,
  decode_channel_packet(Rest, Channel#channel{msg = <<Msg/binary, Chunk/binary>>}, State).



% When chunked packet hasn't arived, just accumulate it
decode_channel_packet(Rest, #channel{msg = Msg, length = Length} = Channel, #rtmp_socket{channels = Channels} = State) when size(Msg) < Length ->
  NextChannelList = array:set(Channel#channel.id, Channel, Channels),
  rtmp:decode(State#rtmp_socket{channels=NextChannelList}, Rest);

% Work with packet when it has accumulated and flush buffers
decode_channel_packet(Rest, #channel{msg = Msg, length = Length} = Channel, #rtmp_socket{channels = Channels} = State) when size(Msg) == Length ->
  {NewState, Message} = command(Channel, State), % Perform Commands here
  NextChannelList = array:set(Channel#channel.id, Channel#channel{msg = <<>>}, Channels),
  {NewState#rtmp_socket{channels=NextChannelList}, Message, Rest}.
  
extract_message(#channel{id = Id, timestamp = Timestamp, stream_id = StreamId}) -> #rtmp_message{channel_id = Id, timestamp = Timestamp, stream_id = StreamId}.
  

command(#channel{type = ?RTMP_TYPE_CHUNK_SIZE, msg = <<ChunkSize:32/big-integer>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State#rtmp_socket{client_chunk_size = ChunkSize}, Message#rtmp_message{type = chunk_size, body = ChunkSize}};

command(#channel{type = ?RTMP_TYPE_ACK_READ, msg = <<BytesRead:32/big-integer>>} = Channel, #rtmp_socket{previous_ack = Prev} = State) ->
  TimeNow = erlang:now(),
  Time = timer:now_diff(TimeNow, Prev)/1000,
  Speed = round(BytesRead*1000 / Time),
  Message = extract_message(Channel),
  AckMessage = #rtmp_message_ack{
    bytes_read = BytesRead,
    previous_ack = Prev,
    current_ack = TimeNow,
    speed = Speed
  },
  {State#rtmp_socket{previous_ack = erlang:now(), current_speed = Speed}, Message#rtmp_message{type = ack_read, body = AckMessage}};

command(#channel{type = ?RTMP_TYPE_WINDOW_ACK_SIZE, msg = <<WindowSize:32/big-integer>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = window_size, body = WindowSize}};

command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<?RTMP_CONTROL_STREAM_BEGIN:16, StreamId:32>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = stream_begin, stream_id = StreamId}};

command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<?RTMP_CONTROL_STREAM_EOF:16, StreamId:32>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = stream_end, stream_id = StreamId}};

command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<?RTMP_CONTROL_STREAM_BUFFER:16, StreamId:32, BufferSize:32>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State#rtmp_socket{client_buffer = BufferSize}, Message#rtmp_message{type = buffer_size, body = BufferSize, stream_id = StreamId}};

command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<?RTMP_CONTROL_STREAM_RECORDED:16, StreamId:32>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State#rtmp_socket{pinged = false}, Message#rtmp_message{type = stream_recorded, stream_id = StreamId}};

command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<?RTMP_CONTROL_STREAM_PING:16, Timestamp:32>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = ping, body = Timestamp}};

command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<?RTMP_CONTROL_STREAM_PONG:16, Timestamp:32>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State#rtmp_socket{pinged = false}, Message#rtmp_message{type = pong, body = Timestamp}};

	


command(#channel{type = ?RTMP_TYPE_CONTROL, msg = <<EventType:16/big-integer, Body/binary>>} = Channel, State) ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = control, body = {EventType, Body}}};


command(#channel{type = Type, delta = 0} = Channel, State) when (Type =:= ?RTMP_TYPE_AUDIO) or (Type =:= ?RTMP_TYPE_VIDEO) or (Type =:= ?RTMP_TYPE_METADATA_AMF0) ->
  Message = extract_message(Channel),
  {State, Message#rtmp_message{type = broken_meta}};

command(#channel{type = Type, length = 0} = Channel, State) when (Type =:= ?RTMP_TYPE_AUDIO) or (Type =:= ?RTMP_TYPE_VIDEO) or (Type =:= ?RTMP_TYPE_METADATA_AMF0) ->
  Message = extract_message(Channel),
  {State, Message#rtmp_message{type = broken_meta}};

command(#channel{type = ?RTMP_TYPE_AUDIO, msg = Body} = Channel, State)	 ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = audio, body = Body}};

command(#channel{type = ?RTMP_TYPE_VIDEO, msg = Body} = Channel, State)	 ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = video, body = Body}};

command(#channel{type = ?RTMP_TYPE_METADATA_AMF0} = Channel, State)	 ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = metadata}};

command(#channel{type = ?RTMP_TYPE_METADATA_AMF3} = Channel, State)	 ->
  Message = extract_message(Channel),
	{State, Message#rtmp_message{type = metadata}};

% Red5: net.rtmp.codec.RTMPProtocolDecoder
% // TODO: Unknown byte, probably encoding as with Flex SOs?
% in.skip(1);
command(#channel{type = ?RTMP_INVOKE_AMF3, msg = <<_, Body/binary>>, stream_id = StreamId} = Channel, State) ->
  Message = extract_message(Channel),
  AMF = decode_funcall(Body, StreamId),
  {State, Message#rtmp_message{type = invoke, body = AMF#rtmp_funcall{version = 3}}};

command(#channel{type = ?RTMP_INVOKE_AMF0, msg = Body, stream_id = StreamId} = Channel, State) ->
  Message = extract_message(Channel),
  {State, Message#rtmp_message{type = invoke, body = decode_funcall(Body, StreamId)}};


command(#channel{type = ?RTMP_TYPE_SO_AMF0, msg = Body} = Channel, State) ->
  Message = extract_message(Channel),
  {State, Message#rtmp_message{type = shared_object, body = decode_shared_object(Body)}};

command(#channel{type = ?RTMP_TYPE_SO_AMF3, msg = Body} = Channel, State) ->
  Message = extract_message(Channel),
  {State, Message#rtmp_message{type = shared_object3, body = decode_shared_object(Body)}};
  
command(#channel{type = Type, msg = Body} = Channel, State) ->
  Message = extract_message(Channel),
  {State, Message#rtmp_message{type = Type, body = Body}}.

decode_funcall(Message, StreamId) ->
	{Command, Rest1} = amf0:decode(Message),
	{InvokeId, Rest2} = amf0:decode(Rest1),
	Arguments = decode_list(Rest2, amf0, []),
	#rtmp_funcall{command = Command, args = Arguments, type = invoke, id = InvokeId, stream_id = StreamId}.
  
  
decode_list(<<>>, _, Acc) -> lists:reverse(Acc);

decode_list(Body, Module, Acc) ->
  {Element, Rest} = Module:decode(Body),
  decode_list(Rest, Module, [Element | Acc]).


encode_shared_object(#so_message{name = Name, version = Version, persistent = true, events = Events}) ->
  encode_shared_object_events(<<(size(Name)):16, Name/binary, Version:32, 2:32, 0:32>>, Events);

encode_shared_object(#so_message{name = Name, version = Version, persistent = false, events = Events}) ->
  encode_shared_object_events(<<(size(Name)):16, Name/binary, Version:32, 0:32, 0:32>>, Events).

encode_shared_object_events(Body, []) ->
  Body;

encode_shared_object_events(Body, [{EventType, Event} | Events]) ->
  EventData = amf0:encode(Event),
  encode_shared_object_events(<<Body/binary, EventType, (size(EventData)):32, EventData/binary>>, Events);

encode_shared_object_events(Body, [EventType | Events]) ->
  encode_shared_object_events(<<Body/binary, EventType, 0:32>>, Events).


decode_shared_object(<<Length:16, Name:Length/binary, Version:32, 2:32, _:32, Events/binary>>) ->
  decode_shared_object_events(Events, #so_message{name = Name, version = Version, persistent = true});

decode_shared_object(<<Length:16, Name:Length/binary, Version:32, 0:32, _:32, Events/binary>>) ->
  decode_shared_object_events(Events, #so_message{name = Name, version = Version, persistent = false}).

decode_shared_object_events(<<>>, #so_message{events = Events} = Message) ->
  Message#so_message{events = lists:reverse(Events)};

decode_shared_object_events(<<EventType, 0:32, Rest/binary>>, #so_message{events = Events} = Message) ->
  decode_shared_object_events(Rest, Message#so_message{events = [EventType|Events]});

decode_shared_object_events(<<EventType, EventDataLength:32, EventData:EventDataLength/binary, Rest/binary>>,
  #so_message{events = Events} = Message) ->
  Event = amf0:decode(EventData),
  decode_shared_object_events(Rest, Message#so_message{events = [{EventType, Event}|Events]}).