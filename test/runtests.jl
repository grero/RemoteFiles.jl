using RemoteFiles
using Test
using JLD2


@testset "Server" begin
    sftp_path = RemoteFiles.sftp"grero@WorkingMemoryData:6494:/volume1/NewWorkingMemoryData"
    @test sftp_path.username == "grero"
    @test sftp_path.hostname == "WorkingMemoryData"
    @test sftp_path.port == 6494
    @test sftp_path.path == "/volume1/NewWorkingMemoryData"

    sftp_path = RemoteFiles.sftp"grero@WorkingMemoryData:/volume1/NewWorkingMemoryData"
    @test sftp_path.username == "grero"
    @test sftp_path.hostname == "WorkingMemoryData"
    @test sftp_path.port == 22
    @test sftp_path.path == "/volume1/NewWorkingMemoryData"

    sftp_path = RemoteFiles.sftp"WorkingMemoryData:/volume1/NewWorkingMemoryData"
    @test sftp_path.username == ""
    @test sftp_path.hostname == "WorkingMemoryData"
    @test sftp_path.port == 22
    @test sftp_path.path == "/volume1/NewWorkingMemoryData"
end

@testset "session" begin
    open("/tmp/testfile.txt","w") do f
        write(f, "This is a test")
    end
    fsize, data = RemoteFiles.ssh_session("localhost", 22, RemoteFiles.functions) do session
        RemoteFiles.sftp_session(session) do sftp_session
            RemoteFiles.sftp_open(sftp_session, "/tmp/testfile.txt", 0) do file
                ff = RemoteFiles.SFTPFile(file, true)
                bytes = Vector{UInt8}(undef, 14)
                unsafe_read(ff, pointer(bytes), 14)
                @test bytes == UInt8[0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x61, 0x20, 0x74, 0x65, 0x73, 0x74]
            end
            RemoteFiles.sftp_open(sftp_session, "/tmp/testfile.txt", 0) do file
                fsize = RemoteFiles.sftp_filesize(file)
                bytes = RemoteFiles.sftp_read(file, 100)
                fsize, bytes
            end
        end
    end
    @test data == UInt8[0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x61, 0x20, 0x74, 0x65, 0x73, 0x74]
    @test fsize == 0x000000000000000e
    ff = open(sftp"localhost:/tmp/testfile.txt")
    data2 = read(ff, 14)
    @test data2 == data
    close(ff)
    data3 = open(sftp"localhost:/tmp/testfile.txt") do ff
        read(ff, 14)
    end
    @test data3 == data
    rm("/tmp/testfile.txt")
end

@testset "JLD2" begin
    tdir = tempdir()
    cd(tdir) do
        a = 1
        b = [1,2,3]
        c = "hello"
        @save "test.jl2" a b c
    end
    ssh_session = RemoteFiles.ssh_session("localhost",22)
    sftp_session = RemoteFiles.sftp_session(ssh_session)
    try
        JLD2.jldopen(joinpath(tdir, "test.jl2"), false, false, false, RemoteFiles.SFTPFile, sftp_session, nothing, false, false) do jfile
            @test jfile["a"] == 1
            @test jfile["b"] == [1,2,3]
            @test jfile["c"] == "hello"
            # need to close everything now before the session closes
        end
    finally
        RemoteFiles.disconnect(sftp_session)
        RemoteFiles.disconnect(ssh_session)
    end
end
