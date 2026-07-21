function updateVMWorldFile(vmIP, vmUser, vmPassword, remoteDir, remoteFile, newMu, newLum, newTransp)
    sftpObj = sftp(vmIP, vmUser, 'Password', vmPassword);

    try
        cd(sftpObj, remoteDir);
        mget(sftpObj, remoteFile);

        fileText = fileread(remoteFile);

        patternFric = '(<friction>\s*<ode>\s*<mu>)[\d\.]+(</mu>\s*<mu2>)[\d\.]+(</mu2>)';
        replacementFric = sprintf('$1%.6f$2%.6f$3', newMu, newMu);
        fileText = regexprep(fileText, patternFric, replacementFric);

        patternAmbient = '(<ambient>\s*)[\d\.]+\s+[\d\.]+\s+[\d\.]+(\s+[\d\.]+\s*</ambient>)';
        replacementAmbient = sprintf('$1%.6f %.6f %.6f$2', newLum, newLum, newLum);
        fileText = regexprep(fileText, patternAmbient, replacementAmbient);

        patternTransparency = '(<transparency>\s*)[\d\.]+(\s*</transparency>)';
        replacementTransparency = sprintf('$1%.6f$2', newTransp);
        fileText = regexprep(fileText, patternTransparency, replacementTransparency);

        fid = fopen(remoteFile, 'w');
        if fid == -1
            error('Cannot open local world file for writing.');
        end
        fprintf(fid, '%s', fileText);
        fclose(fid);

        mput(sftpObj, remoteFile);
        delete(remoteFile);

    catch ME
        try
            if exist(remoteFile, 'file')
                delete(remoteFile);
            end
        catch
        end
        close(sftpObj);
        rethrow(ME);
    end

    close(sftpObj);
end
