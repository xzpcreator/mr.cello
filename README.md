# 提琴先生・排課系統（線上版）部署步驟

資料夾內三個檔案：`index.html`（網頁）、`config.js`（連線設定）、`supabase-setup.sql`（資料庫設定）。

## 1. 建立資料庫（約 5 分鐘）
1. 到 supabase.com 註冊並建立新專案，地區選離台灣近的（例如 Tokyo 或 Singapore），記下資料庫密碼。
2. 左側 **SQL Editor** → New query → 貼上 `supabase-setup.sql` 全部內容 → **Run**。

## 2. 設定登入
1. **Authentication → Users → Add user**：輸入你自己的信箱與密碼，勾選 *Auto Confirm User*。
2. **Authentication → Sign In / Providers**：把 *Allow new users to sign up* 關閉，避免陌生人自行註冊。
3. 回到 SQL Editor，執行（信箱換成你的）：
   `update public.profiles set role = 'admin' where email = 'you@example.com';`
4. 之後每位同事或老師，都在 Add user 建立帳號，再用 SQL 指定角色（見 `supabase-setup.sql` 最後的註解）。

## 3. 填入連線設定
Supabase 左下 **Project Settings → API**，把 **Project URL** 與 **anon / publishable key** 填進 `config.js`。

## 4. 上線
- 最簡單：到 netlify.com 的 Netlify Drop，把整個資料夾拖進去，馬上得到網址。
- 也可用 Cloudflare Pages 或 Vercel；之後想綁自己的網域都可以。
- 上線後回 Supabase：**Authentication → URL Configuration** 把你的網站網址填進 Site URL。

## 角色權限
| 角色 | 課表 | 排課／編輯 | 老師與學生名單 | 課時費與統計 |
|---|---|---|---|---|
| 管理者 admin | 全部 | ✔ | ✔ | ✔ |
| 櫃檯 staff | 全部 | ✔ | ✔ | ✘ |
| 老師 teacher | 只看自己的課 | ✘ | ✘ | ✘ |

權限由資料庫強制執行，不是只把按鈕藏起來；課時費存在獨立資料表，非管理者連資料都讀不到。
原本的共用密碼 091089 已移除，改由管理者角色控制。

## 衝突檢查
同一天同一時段，同一琴房、同一老師、同一學生不可重複；鋼琴課只能 A／C；團體班只能 C。
這些規則同時寫在資料庫裡，所以兩個人同一秒排同一時段，後送出的會被擋下並提示重新載入。

## 注意事項
- `anon key` 本來就是公開的，安全靠上面的權限規則；`service_role` 金鑰絕不能放進網頁。
- 學生姓名與費用屬個人資料，請只開通必要的人，並留意個資法（尤其是未成年學生）。
- 免費方案的備份與保留期限有限，建議定期自己匯出資料（Table Editor 可匯出 CSV）；專案若長期沒人使用也可能被暫停，請查看 Supabase 當前方案說明。
- 目前沒有「在網頁裡管理帳號」的畫面，開通帳號與角色需用 Supabase 後台。需要的話可以再加。

## 用 GitHub 上線（已連結 GitHub 時）
1. 在 GitHub 建立新的 repository（例如 `mr-violin`），把本資料夾的 4 個檔案放進去根目錄。
2. 在 Netlify、Vercel 或 Cloudflare Pages 選 *Import from Git*，選這個 repository；不需要建置指令，輸出資料夾留空或填 `/`。
3. 之後每次在 GitHub 更新檔案，網站會自動重新發佈。
4. 若用 GitHub Pages，免費方案要求 repository 為公開。`config.js` 內的 anon key 本來就是公開用的，資料安全靠資料庫權限；但請不要把任何學生資料或 service_role 金鑰放進 repository。
