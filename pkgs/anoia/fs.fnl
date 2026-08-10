(local ll (require :lualinux))
(import-macros { :  define-tests : expect : expect= } :anoia.assert)

(local S_IFMT   0xf000)
(local S_IFSOCK 0xc000)
(local S_IFLNK  0xa000)
(local S_IFREG  0x8000)
(local S_IFBLK  0x6000)
(local S_IFDIR  0x4000)
(local S_IFCHR  0x2000)
(local S_IFIFO  0x1000)

(macro errno-check [x]
  `(match ,x
     val# val#
     (nil errno#) (assert nil (.. "system call failed, errno=" errno#))
     ))

(fn ifmt-bits [mode] (and mode (band mode 0xf000)))

;; returns nil if the pathname doesn't exist
(fn file-type [pathname stat-flag]
  "symbol describing the file type of pathname as detected by lstat(2). Pass non-nil second arg to use stat(2) instead"
  (. {
      S_IFDIR :directory
      S_IFSOCK :socket
      S_IFLNK :link
      S_IFREG :file
      S_IFBLK :block-device
      S_IFCHR :character-device
      S_IFIFO :fifo
      }
     (ifmt-bits (ll.lstat3 pathname (if stat-flag 1)))))

(fn directory? [pathname]
  (= (file-type pathname) :directory))

(fn mktree [pathname]
  (if (or (= pathname "") (= pathname "/"))
      (error (.. "can't mkdir " pathname)))

  (case (file-type pathname :stat)
    :directory true
    ty (error (.. pathname " exists as " ty ", not a directory"))
    nil
    (let [parent (string.gsub pathname "/[^/]+/?$" "")]
      (or (= (file-type parent :stat) :directory) (mktree parent))
      (errno-check (ll.mkdir pathname)))))

(fn dir [name]
  (let [dp (errno-check (ll.opendir name) name)]
    (fn []
      (case (ll.readdir dp)
        (name filetype) (values name filetype)
        (nil err) (do (if (> err 0) (print "ERR" err)) (ll.closedir dp) nil)
        ))))

(fn rmtree [pathname]
  (case (file-type pathname)
    nil true
    :directory
    (do
      (each [f (dir pathname)]
        (when (not (or (= f ".") (= f "..")))
          (rmtree ( .. pathname "/" f)))
        (ll.rmdir pathname)))
    :file
    (os.remove pathname)
    :link
    (os.remove pathname)
    unknown
    (error (.. "can't remove " pathname " of mode \"" unknown "\""))))

;; lualinux doesn't publish access(2), this is not exactly
;; the same but will suffice until we can add it
(fn executable? [f]
  (let [statbuf {}
        stat (ll.lstat f statbuf 1)]
    (and stat (> (band (. stat 3) 73) 0)))) ; \0111

(fn find-executable [exe search-path]
  (accumulate [full-path nil
               p (string.gmatch search-path "(.-):")]
    (or full-path (let [f (.. p "/" exe)] (and (executable? f) f)))))

(define-tests
  (let [p (find-executable "yes" (os.getenv "PATH"))]
    (expect (string.match p "coreutils.+bin/yes$"))))

(define-tests
  (let [setup (os.execute "mkdir foo; ln -s foo bar")]
    (mktree "bar")))

{
 : mktree
 : rmtree
 : directory?
 : dir
 : file-type
 : find-executable
 :symlink (fn [from to] (ll.symlink from to))
 }
