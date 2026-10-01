require 'csv'

EVALUATION_PATTERNS = [
  # --- 1. 表記揺れ ---
  {
    category: '表記揺れ',
    subcategory: '文字種の揺れ',
    query: 'リンゴに含まれる成分と健康効果',
    doc: '林檎（りんご）はビタミンCを豊富に含み、健康維持に優れています。',
    expected_match: true,
    result_label: 'ヒットすべき（正解）',
    reason: '文字種（カタカナ/漢字）の違いのみで、指している概念（果物のりんご）が完全一致しているため。'
  },
  {
    category: '表記揺れ',
    subcategory: '長音の有無',
    query: 'Webサーバの初期セットアップ手順',
    doc: 'Linux環境におけるWebサーバーの構築手順および初期設定について。',
    expected_match: true,
    result_label: 'ヒットすべき（正解）',
    reason: 'JIS規格等による末尾長音の有無（サーバ/サーバー）であり、意味は全く同一であるため。'
  },
  {
    category: '表記揺れ',
    subcategory: '半角・全角',
    query: '１１月のイベント開催スケジュール',
    doc: '11月中に実施される地域イベントおよびセミナーの一覧情報です。',
    expected_match: true,
    result_label: 'ヒットすべき（正解）',
    reason: '全角数字「１１」と半角数字「11」の文字種差であり、同じ月を指定しているため。'
  },

  # --- 2. シノニム ---
  {
    category: 'シノニム',
    subcategory: '略称・正式名称',
    query: 'スマホのバッテリー持続時間を延ばす方法',
    doc: 'スマートフォンの電池消費を抑え、稼働時間を長くするための設定ガイド。',
    expected_match: true,
    result_label: 'ヒットすべき（正解）',
    reason: '略称（スマホ）と正式名称（スマートフォン）であり、同じ対象を指しているため。'
  },
  {
    category: 'シノニム',
    subcategory: '外来語・言い換え',
    query: '明日の会議のレジュメを作成する',
    doc: '明日のプロジェクトミーティング用に、要約資料を事前配布します。',
    expected_match: true,
    result_label: 'ヒットすべき（正解）',
    reason: '「レジュメ」と「要約資料」は文脈上完全に同義の言い換えであるため。'
  },

  # --- 3. ネガティブテスト ---
  {
    category: 'ネガティブ',
    subcategory: '型番・品番の違い',
    query: '型番 A-100 の取扱説明書をダウンロード',
    doc: '型番 A-200 の仕様書および取扱説明書ダウンロードページです。',
    expected_match: false,
    result_label: 'ヒット不可（誤ヒット＝不正解）',
    reason: 'ベクトル表現では文脈が極めて似てしまうが、製品型番（A-100とA-200）が異なるため不適合。'
  },
  {
    category: 'ネガティブ',
    subcategory: '否定条件の無視',
    query: '東京発を【含まない】観光ツアー特集',
    doc: '東京発を含む、全国の主要都市から出発する人気観光ツアー特集。',
    expected_match: false,
    result_label: 'ヒット不可（誤ヒット＝不正解）',
    reason: '「含まない」という否定文脈を無視して「東京発のツアー」と混同して判定してしまうため。'
  },
  {
    category: 'ネガティブ',
    subcategory: '数値・価格帯のミスマッチ',
    query: '1000円以下で楽しめる手軽なランチ',
    doc: 'お一人様10,000円からご提供する高級シェフのディナーコース。',
    expected_match: false,
    result_label: 'ヒット不可（誤ヒット＝不正解）',
    reason: '金額の桁数（1,000円 vs 10,000円）および時間帯（ランチ vs ディナー）の条件を満たさないため。'
  }
].freeze

def generate_evaluated_csv(target_count = 30, output_file = 'search_test_evaluated.csv')
  headers = %w[id category subcategory query target_document expected_match result_label judgment_reason]

  CSV.open(output_file, 'w', write_headers: true, headers: headers) do |csv|
    (1..target_count).each do |i|
      pattern = EVALUATION_PATTERNS[(i - 1) % EVALUATION_PATTERNS.size]

      csv << [
        i,
        pattern[:category],
        pattern[:subcategory],
        pattern[:query],
        pattern[:doc],
        pattern[:expected_match],
        pattern[:result_label],
        pattern[:reason]
      ]
    end
  end
end

generate_evaluated_csv(30)
