# DLT.jl
Julia package for reading DLT files

## What is it good for?

This project aims for providing a julia implementation for reading DLT files like it's origin https://github.com/COVESA/dlt-viewer but for command line only.

## Why it was done?

The purpose is learning julia language and providing a tool for analysis.

## How to use it?

It provides functionality to iterate over log messages within a given file:

```julia
for msg in DLT.read_resumable(file_name)
    if msg.type == "LOG"
        content = DLT.msg_content(msg.noar, msg.msg)
        if contains(content, "...")
            # ...
        end
    end
end
```

```julia
for (date, time, ecu, app, ctx, vrb, typ, nfo, noar, msg) in DLT.read_resumable(file_name)
    if typ == "LOG"
        println(date, " ", DLT.msg_content(noar, msg))
    end
end
```


```julia
for msg in DLT.read_channel(file_name)
    if msg.type == "LOG"
        content = DLT.msg_content(msg.noar, msg.msg)
        if contains(content, "...")
            # ...
        end
    end
end
```

```julia
for (date, time, ecu, app, ctx, vrb, typ, nfo, noar, msg) in DLT.read_channel(file_name)
    if typ == "LOG"
        println(date, " ", DLT.msg_content(noar, msg))
    end
end
```

