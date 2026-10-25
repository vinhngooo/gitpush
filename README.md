# GitHub Push Tool

Ứng dụng Windows: **chọn folder → dán link repo GitHub → bấm CHẠY**.

## Mở ứng dụng

Nhấp đúp **GitHub Push.exe**. Có thể dùng **Mo-GitHub-Push.cmd** nếu cần.

Giữ các file trong cùng folder. Nếu dùng bản ZIP, giải nén toàn bộ trước khi mở. Tool dùng Windows PowerShell 5.1 và .NET Framework có sẵn trên Windows, không cần cài Python/Node.js.

## Sử dụng

1. Bấm **Chọn folder...**, chọn thư mục gốc chứa code.
2. Dán link repo đã tồn tại, ví dụ `https://github.com/your-name/your-repo`. Repo có thể public hoặc private; tài khoản cần có quyền push.
3. Bấm **Chạy**, hoặc Enter khi đang nhập.
4. Bấm **Xem thêm** khi cần xem tiến trình, sửa nội dung commit hoặc mở các tùy chọn. Bấm **Thu gọn** để trở lại cửa sổ nhỏ.

Lần đầu chưa có tài khoản trên máy: mở **Xem thêm**, bấm **Đăng nhập**, hoàn tất trong trình duyệt. Tool sử dụng Git Credential Manager đi kèm Git for Windows. Không nhập token/mật khẩu vào tool. Nếu Git chưa cài: tải từ [Git for Windows](https://git-scm.com/download/win), cài cả Git Credential Manager, rồi mở lại ứng dụng.

Nếu Git chưa có tên/email: mở **Xem thêm**, bấm **Tác giả** và nhập tên cùng email. Có thể lấy email noreply của bạn từ GitHub → Settings → Emails. Tên/email được lưu vào cấu hình Git cục bộ của folder được push; để trống cả hai để dùng cấu hình Git hiện tại.

Tool nhớ folder, link repo và tên/email; nội dung commit được nhập riêng cho mỗi lần chạy. Cấu hình và log nằm trong `.state` bên cạnh ứng dụng. Folder `.state` đã được loại trừ qua file `.gitignore` đi kèm. Không xóa log trong lúc thao tác đang chạy.

## Tool thực hiện những gì?

- Kiểm tra link, folder gốc, trạng thái Git và kết nối tới repo trước khi thêm file/commit.
- Với folder do tài khoản Windows khác tạo (ví dụ sandbox), chỉ tin cậy đúng folder đã chọn trong từng lệnh Git; không đổi owner và không sửa safe.directory toàn máy.
- Folder chưa có Git: tạo repo trên nhánh `main`. Folder đã có Git: dùng nhánh hiện tại.
- Nhánh đích chưa có trên GitHub: tạo nhánh đó khi push. Nếu GitHub đã có lịch sử riêng (ví dụ đã tạo README trên web) và folder chưa có lịch sử tương ứng: dừng để bạn clone repo rồi đưa code vào.
- Nếu origin đang trỏ tới repo khác: hỏi xác nhận trước khi thay đổi. Với cùng repo, chuẩn hóa origin sang HTTPS để dùng đăng nhập trình duyệt.
- Thêm quy tắc bỏ qua `.env`, khóa riêng phổ biến, `node_modules`, môi trường Python vào cuối `.gitignore`, giữ các quy tắc sẵn có. Không tự loại bỏ file đã được Git theo dõi.
- Thêm mọi thay đổi được phép, gồm cả file bị xóa; commit nếu có thay đổi rồi push **một nhánh hiện tại**. Lần đầu chạy có thể tạo commit bổ sung `.gitignore`.
- Không có thay đổi: vẫn đẩy các commit hiện có, không tạo commit rỗng.
- Không force push, không tự pull/merge/rebase. Giữ commit cục bộ nếu push thất bại.

## Khi tool dừng

- **GitHub có commit mới / lịch sử khác:** đồng bộ code và xử lý xung đột bằng công cụ Git bạn dùng rồi thử lại.
- **Sai quyền / repo không tồn tại:** kiểm tra link và đăng nhập đúng tài khoản có quyền ghi. Kiểm tra kết nối ban đầu chỉ xác nhận đọc được repo; quyền ghi được GitHub kiểm tra lúc push.
- **Nhánh được bảo vệ:** chuyển sang nhánh được phép và tạo Pull Request theo quy định repo.
- **Có file bí mật đang được theo dõi hoặc trong lịch sử:** kiểm tra file/lịch sử trước khi push. `.gitignore` không xóa nội dung đã commit. Kiểm tra của tool dựa vào một số tên file phổ biến, không thay thế việc kiểm tra nội dung code.
- **Có `pushurl`, nhiều URL hoặc cấu hình `url.*.insteadOf/pushInsteadOf` khớp repo:** kiểm tra cấu hình Git trước để bảo đảm đúng đích. Tool không tự xóa các cấu hình này.
- **Git hooks, ký commit, Git LFS hoặc chính sách tổ chức báo lỗi:** hoàn tất cấu hình theo yêu cầu repo. Tool giữ nguyên các cơ chế đó.

Git chạy ở nền; bấm **Xem thêm** để xem bước đang làm và lỗi chi tiết. Tác vụ Git có thời gian chờ tối đa 10 phút cho mỗi lệnh. Chờ Git hoàn tất trước khi đóng cửa sổ. Không cần mở CMD thủ công.

## Kiểm tra và build lại

Chạy bằng Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Worker.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\App.ps1 -SmokeTest -PreviewPath "$env:TEMP\github-push-preview.png"
```

Tests sử dụng bare repository trong thư mục tạm, không đăng nhập hoặc đẩy code lên GitHub thật. `Core.ps1` có chế độ local remote dành cho kiểm thử; giao diện chỉ nhận repo GitHub.

Mã launcher ở `Launcher.cs`. Để build lại, chuyển file EXE cũ sang chỗ khác rồi chạy `Build.ps1` bằng Windows PowerShell 5.1.

Tài liệu nền: [Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager), [quy tắc URL của Git](https://git-scm.com/docs/git-config).
