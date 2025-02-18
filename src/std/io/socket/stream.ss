;;; -*- Gerbil -*-
;;; © vyzo
;;; stream sockets
(import (only-in :gerbil/gambit/exceptions display-exception)
        :std/error
        :std/os/socket
        :std/os/fd
        ../interface
        ./types
        ./basic)
(export #t)

(def state-closed-in 1)
(def state-closed-out 2)
(def state-closed-inout 3)

;; generic stream sockets
(def (stream-socket-recv ssock output output-start output-end flags)
  (with-basic-socket-read-lock ssock
    (when (stream-socket-closed? ssock state-closed-in)
      (raise-io-error 'stream-socket-recv "socket input has been shutdown"))
    (let (sock (&basic-socket-sock ssock))
      (let lp ()
        (let (read (socket-recv sock output output-start output-end flags))
          (cond
           (read)
           ((basic-socket-wait-io! ssock (fd-io-in sock) (&basic-socket-timeo-in ssock))
            (when (stream-socket-closed? ssock state-closed-in)
              (raise-io-error 'stream-socket-recv "socket input has been shutdown"))
            (lp))
           (else
            (raise-timeout 'stream-socket-recv "receive timeout"))))))))

(def (stream-socket-send ssock input input-start input-end flags)
  (with-basic-socket-read-lock ssock
    (when (stream-socket-closed? ssock state-closed-out)
      (raise-io-error 'stream-socket-send "socket output has been shutdown"))
    (let (sock (&basic-socket-sock ssock))
      (let lp ()
        (let (wrote (socket-send sock input input-start input-end (fxior flags MSG_NOSIGNAL)))
          (cond
           (wrote)
           ((basic-socket-wait-io! ssock (fd-io-out sock) (&basic-socket-timeo-out ssock))
            (when (stream-socket-closed? ssock state-closed-out)
              (raise-io-error 'stream-socket-send "socket output has been shutdown"))
            (lp))
           (else
            (raise-timeout 'stream-socket-send "send timeout"))))))))

(def (stream-socket-get-reader ssock)
  (Reader (make-stream-socket-reader ssock)))

(def (stream-socket-get-writer ssock)
  (Writer (make-stream-socket-writer ssock)))

(def (stream-socket-shutdown ssock dir)
  (let* ((how
          (case dir
            ((in) SHUT_RD)
            ((out) SHUT_WR)
            ((inout) SHUT_RDWR)
            (else
             (error "Bad argument; direction must be in, out, or inout"))))
         (state-dir (direction->state dir)))
    (with-basic-socket-write-lock ssock
      (unless (stream-socket-closed? ssock state-dir)
        (with-catch void
          (cut socket-shutdown (&basic-socket-sock ssock) how))
        (stream-socket-close/lock ssock state-dir)))))

(def (stream-socket-close ssock)
  (with-basic-socket-write-lock ssock
    (unless (stream-socket-closed? ssock state-closed-inout)
      (stream-socket-close/lock ssock state-closed-inout))))

;; state management
(def (stream-socket-closed? ssock state-dir)
  ;; caller holds the lock (read or write)
  (let (state-closed-dir (fxand (&stream-socket-state ssock) state-dir))
    (fx= state-dir state-closed-dir)))

(def (stream-socket-close/lock ssock state-dir)
  ;; caller holds the write lock
  (let (state-closed-dir (fxior (&stream-socket-state ssock) state-dir))
    (set! (&stream-socket-state ssock) state-closed-dir)
    (when (fx= state-closed-dir state-closed-inout)
      (basic-socket-close/lock ssock))))

(def (direction->state dir)
  (case dir
    ((in) state-closed-in)
    ((out) state-closed-out)
    (else state-closed-inout)))

;; stream socket reader
(def (stream-socket-read sreader output output-start output-end input-need)
  (let (ssock (stream-socket-reader-sock sreader))
    (let lp ((output-start output-start) (input-need input-need) (result 0))
      (if (fx< output-start output-end)
        (let (read (stream-socket-recv ssock output output-start output-end 0))
          (cond
           ((fx= read 0)
            (if (fx> input-need result)
              (raise-io-error 'stream-socket-read "premature end of input" input-need)
              result))
           ((fx> read input-need)
            (fx+ result read))
           (else
            (lp (fx+ output-start read) (fx- input-need read) (fx+ result read)))))
        result))))

(def (stream-socket-close-reader sreader)
  (stream-socket-shutdown (&stream-socket-reader-sock sreader) 'in))

;; stream socket writer
(def (stream-socket-write swriter input input-start input-end)
  (let (ssock (stream-socket-writer-sock swriter))
    (let lp ((input-start input-start) (result 0))
      (if (fx< input-start input-end)
        (let (wrote (stream-socket-send ssock input input-start input-end 0))
          (lp (fx+ input-start wrote) (fx+ result wrote)))
        result))))

(def (stream-socket-close-writer swriter)
  (stream-socket-shutdown (&stream-socket-writer-sock swriter) 'out))
