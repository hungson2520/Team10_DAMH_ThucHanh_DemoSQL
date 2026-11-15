
--- GIỚI THIỆU KHÁI QUÁT VỀ DỮ LIỆU  Instacart Market Basket Analysis
SELECT * FROM ORDERS LIMIT 1
SELECT * FROM order_products_prior LIMIT 1
SELECT * FROM aisles 
SELECT * FROM DEPARTMENTS 
SELECT * FROM PRODUCTS LIMIT 1

---DEMO B-TREE
/*Ý nghĩa: Xác định Top 10 sản phẩm có số lần được khách hàng đặt mua lại nhiều nhất 
(reordered = 1) trên toàn bộ lịch sử giao dịch của hệ thống  */
DROP INDEX IF EXISTS idx_opp_reordered_product;

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.product_id,
    p.product_name,
    COUNT(*) AS so_lan_dat_lai
FROM order_products_prior opp
JOIN products p ON p.product_id = opp.product_id
WHERE opp.reordered = 1
GROUP BY p.product_id
ORDER BY so_lan_dat_lai DESC
LIMIT 10;

CREATE INDEX idx_opp_reordered_product 
ON order_products_prior USING BTREE (reordered, product_id);

----DEMO HASH INDEX
/*Ý nghĩa :Trích xuất toàn bộ lịch sử mua sắm chi tiết của 1 khách hàng cụ thể(  user_id = 150000) 
theo trình tự đơn hàng (order_number tăng dần), bao gồm thời điểm đặt hàng (thứ, giờ, khoảng 
cách ngày giữa các đơn) và danh sách tên sản phẩm kèm trạng thái mua lại (reordered). */
--TEST HASH INDEX
DROP INDEX IF EXISTS idx_orders_user_id_hash;




-- : Lấy kế hoạch thực thi và thời gian chi tiết
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    o.user_id,
    o.order_number,
    o.order_dow,
    o.order_hour_of_day,
    o.days_since_prior_order,
    p.product_name,
    opp.reordered
FROM orders o
JOIN order_products_prior opp ON o.order_id = opp.order_id
JOIN products p ON opp.product_id = p.product_id
WHERE o.user_id = 150000
ORDER BY o.order_number ASC;

CREATE INDEX idx_orders_user_id_hash ON orders USING HASH (user_id);


EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    o.user_id,
    o.order_number,
    o.order_dow,
    o.order_hour_of_day,
    o.days_since_prior_order,
    p.product_name,
    opp.add_to_cart_order,
    opp.reordered
FROM orders o
JOIN order_products_prior opp ON o.order_id = opp.order_id
JOIN products p ON opp.product_id = p.product_id
WHERE o.user_id = 150000
ORDER BY o.order_number ASC, opp.add_to_cart_order ASC;



---JOIN REORDERING
/* Ý nghĩa: Thống kê danh sách các sản phẩm thuộc 1 ngành hàng ( ví dụ: Rau củ quả tươi 
(department = 'produce')) mà 1 khách hàng cụ thể (ví dụ có mã user_id = 150000)
đã mua lặp lại (reordered = 1), kèm theo tổng số lần mua lại (so_lan_mua_lai) của từng món. */


/*Trường hợp 1: Không sử dụng Join Reordering (Giữ nguyên thứ tự gốc)*/
--- KHÔNG ÁP DỤNG JOIN REORDERING
SET  join_collapse_limit = 1;
SET  enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.department,
    p.product_name,
    COUNT(o.order_id) AS so_lan_mua_lai
FROM departments d
JOIN products p 
    ON d.department_id = p.department_id
JOIN order_products_prior opp 
    ON p.product_id = opp.product_id
JOIN orders o 
    ON opp.order_id = o.order_id
WHERE d.department = 'produce'
  AND opp.reordered = 1
  AND o.user_id = 150000
GROUP BY d.department, p.product_name;
















-- ÁP DỤNG JOIN REORDERING
/*Trường hợp 2: Có sử dụng Join Reordering (Đảo thứ tự phép nối thủ công)*/
SET  join_collapse_limit = 1;
SET  enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.department,
    p.product_name,
    COUNT(o.order_id) AS so_lan_mua_lai
FROM orders o
JOIN order_products_prior opp 
    ON o.order_id = opp.order_id
JOIN products p 
    ON opp.product_id = p.product_id
JOIN departments d 
    ON p.department_id = d.department_id
WHERE o.user_id = 150000
  AND opp.reordered = 1
  AND d.department = 'produce'
GROUP BY d.department, p.product_name;



---- TỐI ƯU HÓA TỰ ĐỘNG BỞI QUERY OPTIMIZER (CẤU HÌNH MẶC ĐỊNH)
/*Trường hợp 3: Hệ quản trị CSDL PostgreSQL tự động tối ưu*/
RESET ALL;
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.department,
    p.product_name,
    COUNT(o.order_id) AS so_lan_mua_lai
FROM departments d
JOIN products p 
    ON d.department_id = p.department_id
JOIN order_products_prior opp 
    ON p.product_id = opp.product_id
JOIN orders o 
    ON opp.order_id = o.order_id
WHERE d.department = 'produce'
  AND opp.reordered = 1
  AND o.user_id = 150000
GROUP BY d.department, p.product_name;




----------------------------------

-- PREDICATE PUSHDOWN
/*:trích xuất danh sách các sản phẩm đã từng được mua lại (reordered = 1) 
trong toàn bộ lịch sử đặt hàng của một khách hàng cụ thể (user_id = 150000),
bao gồm mã đơn hàng (order_id), mã khách hàng (user_id), mã sản phẩm (product_id) 
và trạng thái tái đặt hàng (reordered).*/

/*Trường hợp 1: Không đẩy vị từ lọc (Kết nối bảng trước khi lọc dữ liệu)*/
EXPLAIN (ANALYZE, BUFFERS)
WITH ket_qua_join AS MATERIALIZED (
    SELECT 
        o.order_id,
        o.user_id,
        opp.product_id,
        opp.reordered
    FROM orders o
    JOIN order_products_prior opp ON o.order_id = opp.order_id
)
SELECT *
FROM ket_qua_join
WHERE user_id = 150000
  AND reordered = 1;
/*Trường hợp 2: Có đẩy vị từ lọc (Lọc dữ liệu từng bảng trước khi kết nối)*/
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    o.order_id,
    o.user_id,
    opp.product_id,
    opp.reordered
FROM (
    SELECT order_id, user_id 
    FROM orders 
    WHERE user_id = 150000
) o
JOIN (
    SELECT order_id, product_id, reordered 
    FROM order_products_prior 
    WHERE reordered = 1
) opp ON o.order_id = opp.order_id;





---
---DEMO KHỬ LỒNG TRUY VẤN CON
----

/*Ý nghĩa :tìm ra danh sách các sản phẩm (mã sản phẩm product_id và tên sản phẩm product_name)
mà 1 khách hàng (có mã user_id = 150000) đã mua nhiều hơn 5 lần*/
/*Trường hợp 1: Không khử truy vấn lồng (Sử dụng truy vấn con tương quan)*/
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM (
    SELECT 
        p.product_id,
        p.product_name,
        (
            SELECT COUNT(*)
            FROM order_products_prior opp
            JOIN orders o ON opp.order_id = o.order_id
            WHERE opp.product_id = p.product_id
              AND o.user_id = 150000
        ) AS so_lan_mua
    FROM products p
) sub
WHERE so_lan_mua > 5
ORDER BY product_id ASC;






/*Trường hợp 2: Có khử truy vấn lồng (Chuyển đổi sang JOIN và GROUP BY)*/
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.product_id,
    p.product_name,
    COUNT(opp.order_id) AS so_lan_mua
FROM orders o
JOIN order_products_prior opp ON o.order_id = opp.order_id
JOIN products p ON opp.product_id = p.product_id
WHERE o.user_id = 150000
GROUP BY p.product_id, p.product_name
HAVING COUNT(opp.order_id) > 5
ORDER BY so_lan_mua DESC, p.product_id ASC;


-------------HẾT ---------------------------








