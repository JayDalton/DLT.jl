module DLT

import Pkg
Pkg.add("BufferedStreams")
Pkg.add("ResumableFunctions")

using Core, Dates
using BufferedStreams
using ResumableFunctions

public read_channel, read_resumable
public msg_content, read_statistic

##################### Types #################

dlt_is_htyp_ueh(htyp) = (htyp & 0x01) != 0 # extHeader (0:no,1:yes)
dlt_is_htyp_msbf(htyp) = (htyp & 0x02) != 0 # endian (0:little,1:big)
dlt_is_htyp_weid(htyp) = (htyp & 0x04) != 0 # ecuInStdHead (0:no,1:yes)
dlt_is_htyp_wsid(htyp) = (htyp & 0x08) != 0 # sessIdInStdHead (0:no,1:yes)
dlt_is_htyp_wtms(htyp) = (htyp & 0x10) != 0 # timeInStdHead (0:no,1:yes)

dlt_standard_header_extra_size(htyp) =
    (dlt_is_htyp_weid(htyp) ? 4 : 0) +
    (dlt_is_htyp_wsid(htyp) ? sizeof(UInt32) : 0) +
    (dlt_is_htyp_wtms(htyp) ? sizeof(UInt32) : 0)

const DLT_MSIN_VERB = 0x01 # verbose (0:no,1:yes)
const DLT_MSIN_MSTP = 0x0e # MessageType
const DLT_MSIN_MTIN = 0xf0 # MessageTypeInfo

const DLT_MSIN_MSTP_SHIFT = 1 
const DLT_MSIN_MTIN_SHIFT = 4 

DLT_IS_MSIN_VERB(msin) = ((msin) & DLT_MSIN_VERB)
DLT_GET_MSIN_MSTP(msin) = (((msin) & DLT_MSIN_MSTP) >> DLT_MSIN_MSTP_SHIFT)
DLT_GET_MSIN_MTIN(msin) = (((msin) & DLT_MSIN_MTIN) >> DLT_MSIN_MTIN_SHIFT)

message_type = ["LOG","TRACE","NETWORK","CONTROL","","","",""];
log_info = ["","FATAL","ERROR","WARN","INFO","DEBUG","VERBOSE","","","","","","","","",""];
trace_type = ["","variable","func_in","func_out","state","vfb","","","","","","","","","",""]
nw_trace_type = ["","ipc","can","flexray","most","vfb","","","","","","","","","",""]
control_type = ["","request","response","time","","","","","","","","","","","",""]

const DLT_TYPE_LOG       = 0x00
const DLT_TYPE_APP_TRACE = 0x01
const DLT_TYPE_NW_TRACE  = 0x02
const DLT_TYPE_CONTROL   = 0x03


dlt_arg_size_008(data) = (data & 0x1) == 0x1
dlt_arg_size_016(data) = (data & 0x2) == 0x2
dlt_arg_size_032(data) = (data & 0x3) == 0x3
dlt_arg_size_064(data) = (data & 0x4) == 0x4
dlt_arg_size_128(data) = (data & 0x5) == 0x5

dlt_arg_type_bool(data) =       (data & 0b10000) != 0
dlt_arg_type_signed(data) =     (data & 0b100000) != 0
dlt_arg_type_unsigned(data) =   (data & 0b1000000) != 0
dlt_arg_type_float(data) =      (data & 0b10000000) != 0
dlt_arg_type_array(data) =      (data & 0b100000000) != 0
dlt_arg_type_string(data) =     (data & 0b1000000000) != 0

function get_arg_type(data)::DataType
    dlt_arg_size_128(data) && dlt_arg_type_unsigned(data) && return UInt128
    dlt_arg_size_064(data) && dlt_arg_type_unsigned(data) && return UInt64
    dlt_arg_size_032(data) && dlt_arg_type_unsigned(data) && return UInt32
    dlt_arg_size_016(data) && dlt_arg_type_unsigned(data) && return UInt16
    dlt_arg_size_008(data) && dlt_arg_type_unsigned(data) && return UInt8
    
    dlt_arg_size_128(data) && dlt_arg_type_signed(data) && return Int128
    dlt_arg_size_064(data) && dlt_arg_type_signed(data) && return Int64
    dlt_arg_size_032(data) && dlt_arg_type_signed(data) && return Int32
    dlt_arg_size_016(data) && dlt_arg_type_signed(data) && return Int16
    dlt_arg_size_008(data) && dlt_arg_type_signed(data) && return Int8
    
    dlt_arg_size_064(data) && dlt_arg_type_float(data) && return Float64
    dlt_arg_size_032(data) && dlt_arg_type_float(data) && return Float32
    dlt_arg_size_016(data) && dlt_arg_type_float(data) && return Float16

    dlt_arg_type_bool(data) && dlt_arg_size_008(data) && return Bool

    Nothing
end

##################### Structs ###############

struct MessageBase
    seconds::UInt32
    micros::Int32
    ecu_id::String
end

struct MessageHeader
    len::UInt16
    noar::UInt8
    time::UInt32
    apid::String
    ctid::String
    verb::String
    type::String
    info::String
end

########################## Helper #######################

clean(in::Vector{UInt8}) = replace(String(in), "\0" => "")

function readMessageBase(io::BufferedStreams.BufferedInputStream)
    @assert read(io, 4) == [0x44, 0x4c, 0x54, 0x01] "no DLT file"

    secs = read(io, UInt32) # secs to epoch
    mics = read(io, Int32) # mics of time
    ecu = clean(read(io, 4)) # ecu_id

    MessageBase(secs, mics, ecu)
end

function readMessageHeader(io::BufferedStreams.BufferedInputStream)
    htyp = read(io, UInt8)
    mcnt = read(io, UInt8)
    len = ntoh(read(io, UInt16))

    if dlt_is_htyp_weid(htyp)
        skip(io, 4) # ecu_id
    end
    
    if dlt_is_htyp_wsid(htyp)
        skip(io, sizeof(UInt32)) # session
    end
    
    timestamp::UInt32 = 0
    if dlt_is_htyp_wtms(htyp)
        timestamp = ntoh(read(io, UInt32))
        # skip(io, sizeof(UInt32)) # timestamp
    end

    noar::UInt8 = 0
    apid::AbstractString = ""
    ctid::AbstractString = ""
    verb::AbstractString = ""
    type::AbstractString = ""
    info::AbstractString = ""

    if dlt_is_htyp_ueh(htyp)
        msin = read(io, UInt8)
        noar = read(io, UInt8)
        apid = clean(read(io, 4))
        ctid = clean(read(io, 4))

        # println("type: ", bitstring(msin))
        verb = DLT_IS_MSIN_VERB(msin) != 0 ? "V" : "N"
        type = message_type[DLT_GET_MSIN_MSTP(msin)+1]

        if DLT_GET_MSIN_MSTP(msin) == DLT_TYPE_LOG
            info = log_info[DLT_GET_MSIN_MTIN(msin)+1]
        elseif DLT_GET_MSIN_MSTP(msin) == DLT_TYPE_CONTROL
            info = control_type[DLT_GET_MSIN_MTIN(msin)+1]
        elseif DLT_GET_MSIN_MSTP(msin) == DLT_TYPE_APP_TRACE
            info = trace_type[DLT_GET_MSIN_MTIN(msin)+1]
        elseif DLT_GET_MSIN_MSTP(msin) == DLT_TYPE_NW_TRACE
            info = nw_trace_type[DLT_GET_MSIN_MTIN(msin)+1]
        end
    end

    MessageHeader(len, noar, timestamp, apid, ctid, verb, type, info)
end

function msg_content(noar::Number, bytes::Vector{UInt8})::AbstractString

    output = IOBuffer(truncate=false)

    input = IOBuffer(bytes)
    for i in range(1, noar)

        arg_info = read(input, UInt32)
        # println(bitstring(arg_info))

        if dlt_arg_type_string(arg_info)
            arg_size = read(input, UInt16)
            arg_data = read(input, arg_size)
            write(output, String(arg_data))
        else
            arg_size = get_arg_type(arg_info)
            if something(arg_size) != Nothing
                arg_data = read(input, arg_size)
                write(output, "|$(arg_data)|")
            end
        end
    end

    String(take!(output))
end

########################## Reader ##############################

function read_channel(file::AbstractString)::Channel
    io = BufferedStreams.BufferedInputStream(open(file))

    Channel{NamedTuple}() do c
        while !eof(io)
            base = readMessageBase(io)
            date = Dates.unix2datetime(base.seconds)
            datetime = date + Microsecond(base.micros)
            
            head = position(io)
            header = readMessageHeader(io)
            tail = position(io)
            
            message = read(io, header.len - (tail - head))

            put!(c, (
                date=datetime, 
                time=header.time,
                ecu=base.ecu_id, 
                apid=header.apid, 
                ctid=header.ctid, 
                verb=header.verb, 
                type=header.type, 
                info=header.info, 
                noar=header.noar,
                msg=message
            ))
        end
        close(io)
    end
end

@resumable function read_resumable(file::AbstractString)
    io = BufferedStreams.BufferedInputStream(open(file))
    while !eof(io)
        base = readMessageBase(io)
        date = Dates.unix2datetime(base.seconds)
        datetime = date + Microsecond(base.micros)
        
        head = position(io)
        header = readMessageHeader(io)
        tail = position(io)
        
        message = read(io, header.len - (tail - head))

        @yield (
            date=datetime, 
            time=header.time,
            ecu=base.ecu_id, 
            apid=header.apid, 
            ctid=header.ctid, 
            verb=header.verb, 
            type=header.type, 
            info=header.info, 
            noar=header.noar,
            msg=message
        )
    end
    close(io)
end

@resumable function read_statistic(file::AbstractString)
    io = BufferedStreams.BufferedInputStream(open(file))
    while !eof(io)
        base = readMessageBase(io)
        date = Dates.unix2datetime(base.seconds)
        datetime = date + Microsecond(base.micros)
        
        head = position(io)
        header = readMessageHeader(io)
        tail = position(io)
        
        message_len = header.len - (tail - head)
        skip(io, message_len)

        @yield (
            date=datetime, 
            time=header.time,
            ecu=base.ecu_id, 
            apid=header.apid, 
            ctid=header.ctid, 
            verb=header.verb, 
            type=header.type, 
            info=header.info, 
            noar=header.noar,
            load=message_len
        )
    end
    close(io)
end

end
