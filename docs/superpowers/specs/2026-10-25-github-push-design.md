# GitHub Push Tool

Approved in chat: Vietnamese Windows GUI with folder picker, GitHub URL input, optional commit message, Run button, visible progress, saved last folder/repository, and browser login. User authorized implementation with “oke làm đi”.

Updated by user: use a tiny minimal window without explanatory copy. Default view is 460×242 client pixels with Folder, Link GitHub, Chạy and a short status. Xem thêm reveals progress plus optional commit/login/author/open actions; Thu gọn restores the small window without losing inputs or logs. Detailed errors stay in Xem thêm. Layout lives in Ui.ps1 and runtime behavior remains in App.ps1.

Implementation choice: Windows PowerShell 5.1 + Windows Forms, no dependency installation. Git for Windows and its Credential Manager provide Git and browser login. Launch through a double-click CMD file; keep the GUI responsive using a separate PowerShell worker. Credentials remain with Git Credential Manager.

Run checks exact repository root (never accidentally stage a parent project), validates GitHub HTTPS/SSH input and canonicalizes to HTTPS, checks repository access before staging, initializes a new repository on main when necessary, retains an existing branch, asks before changing an existing origin, honors gitignore and adds starter excludes, refuses tracked common secret files and unfinished Git operations, stages all permitted changes including deletions, commits only when needed, and pushes the current branch without force. A remote divergence stops with an explanation; no automatic pull/merge/rebase. An empty remote or an existing compatible history is supported. Protected branches remain subject to GitHub policy. A successful no-change run may still push existing commits.

Commit author can be configured in a separate dialog and saved; otherwise existing Git configuration is used. No real GitHub push or account login during development: integration tests use bare local repositories. Delivery includes Vietnamese instructions and a portable ZIP.
