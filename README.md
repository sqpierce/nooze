# Nooze

## An application to aggregate news data.

### Assumptions/Observations

1. News files are xml files stored within zip files.

2. The zip file paths are referenced via an auto-generated html file that resides on a server (http://feed.omgili.com/5Rh5AMTrc4Pv/mainstream/posts/).

3. The files are named with millisecond resolution unix timestamp followed by '.zip'.

4. The zip files contain .xml files which are named with an md5 hash of the file contents.

5. Zip files appear to be added every few minutes, and some kind of rotation is deleting files that are more than about four days old.

6. The requirements state that the xml should be posted (un-parsed) to a redis list, therefore, a seperate redis set will be used to store names of xml files already read, as well as zip files already downloaded/processed. (Note: I haven't examined the data to determine whether there's any danger of xml files being repeated across zip files... it seems not, as I count 26479 in the test xml files and the same number of records end up in the xml file set in redis.) So the step of storing the xml files in a set is likely unnecessary.

7. Rather than implement unit testing of the code (which feels a bit OTT for this exercise), testing will be done using a subset of files already downloaded and included (due to the file rotation on the server, specific files cannot be relied upon to be available over time). Using the test_config hash, the script can be run locally and verified by looking in redis.

8. Processed xml files can be removed. Processed zip files can be moved to a separate directory. If required, another cron job could come along periodically and clean up this directory, perhaps deleting files that are more than a week old (in order to keep them around in case problems are discovered).

9. In production, strategies (replication/backups/etc) should be considered to ensure Redis data durability, as we are relying on this as a datastore, depending on requirements and whether we can recover from momentary data loss, etc. With reliable error capturing and monitoring this should not prove to be a problem.

### Requirements

I'm using Ruby 2.2.2 for this exercise, and creating a script which could be run as a cron job (suggest at least daily, if not every few minutes, to catch new zip files).

I'm also using Redis version 2.8.17, which I happened to have installed.
