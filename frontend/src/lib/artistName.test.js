import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeArtistName, findSameNameArtists } from './artistName.js';

// sp_CreateArtist cố ý không đặt UNIQUE trên ArtistName và giao việc chống trùng cho
// tầng ứng dụng. Các test dưới đây khoá đúng hành vi đó: nhận ra biến thể dấu, hoa/
// thường và khoảng trắng, nhưng KHÔNG gộp hai nghệ sĩ thật sự khác nhau.

test('bỏ dấu tiếng Việt để nhận ra cùng một tên', () => {
  assert.equal(normalizeArtistName('Sơn Tùng M-TP'), normalizeArtistName('Son Tung M-TP'));
  assert.equal(normalizeArtistName('Mỹ Tâm'), normalizeArtistName('My Tam'));
});

test("'đ' được quy về 'd' (NFD không tách được ký tự này)", () => {
  assert.equal(normalizeArtistName('Đen Vâu'), normalizeArtistName('Den Vau'));
  assert.equal(normalizeArtistName('Đông Nhi'), normalizeArtistName('dong nhi'));
});

test('không phân biệt hoa/thường và gộp khoảng trắng thừa', () => {
  assert.equal(normalizeArtistName('  HOÀNG   Thùy  '), normalizeArtistName('hoàng thùy'));
  assert.equal(normalizeArtistName('Bích\tPhương'), normalizeArtistName('bích phương'));
});

test('hai nghệ sĩ thật sự khác nhau thì KHÔNG bị gộp', () => {
  assert.notEqual(normalizeArtistName('Sơn'), normalizeArtistName('Sơn Tùng M-TP'));
  assert.notEqual(normalizeArtistName('Tùng'), normalizeArtistName('Sơn Tùng'));
});

test('tên rỗng hoặc chỉ có khoảng trắng thì không cảnh báo gì', () => {
  const artists = [{ artistID: 1, artistName: 'Sơn Tùng M-TP' }];
  assert.deepEqual(findSameNameArtists('', artists), []);
  assert.deepEqual(findSameNameArtists('   ', artists), []);
  assert.equal(normalizeArtistName('   '), '');
});

test('tìm ra mọi bản ghi trùng tên dù khác dấu và khác hoa/thường', () => {
  const artists = [
    { artistID: 7, artistName: 'Sơn Tùng M-TP' },
    { artistID: 9, artistName: 'Son Tung M-TP' },
    { artistID: 11, artistName: 'Mỹ Tâm' },
  ];

  const matches = findSameNameArtists('SON  TUNG m-tp', artists);

  assert.deepEqual(matches.map((a) => a.artistID), [7, 9]);
});

test('thiếu danh mục hoặc bản ghi dị dạng thì trả về rỗng, không ném lỗi', () => {
  assert.deepEqual(findSameNameArtists('Sơn Tùng', null), []);
  assert.deepEqual(findSameNameArtists('Sơn Tùng', []), []);
  assert.deepEqual(findSameNameArtists('Sơn Tùng', [{ artistID: 1 }, {}]), []);
});