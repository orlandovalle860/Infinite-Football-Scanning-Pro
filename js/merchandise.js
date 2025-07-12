// Shopping Cart Functionality
let cart = [];
let cartTotal = 0;

// Cart Icon Toggle
const cartIcon = document.getElementById('cart-icon');
const cartSidebar = document.getElementById('cart-sidebar');
const cartOverlay = document.getElementById('cart-overlay');
const closeCart = document.getElementById('close-cart');

cartIcon.addEventListener('click', () => {
    cartSidebar.classList.add('active');
    cartOverlay.classList.add('active');
});

closeCart.addEventListener('click', () => {
    cartSidebar.classList.remove('active');
    cartOverlay.classList.remove('active');
});

cartOverlay.addEventListener('click', () => {
    cartSidebar.classList.remove('active');
    cartOverlay.classList.remove('active');
});

// Product Quick View Modal
const productModal = document.getElementById('product-modal');
const closeModal = document.querySelector('.close-modal');
const quickViewBtns = document.querySelectorAll('.quick-view-btn');

quickViewBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
        e.preventDefault();
        const productCard = btn.closest('.product-card');
        const productImage = productCard.querySelector('.product-image img').src;
        const productTitle = productCard.querySelector('h3').textContent;
        const productDescription = productCard.querySelector('.product-description').textContent;
        const productPrice = productCard.querySelector('.current-price').textContent;
        
        document.getElementById('modal-product-image').src = productImage;
        document.getElementById('modal-product-title').textContent = productTitle;
        document.getElementById('modal-product-description').textContent = productDescription;
        document.getElementById('modal-product-price').textContent = productPrice;
        
        productModal.style.display = 'block';
    });
});

closeModal.addEventListener('click', () => {
    productModal.style.display = 'none';
});

window.addEventListener('click', (e) => {
    if (e.target === productModal) {
        productModal.style.display = 'none';
    }
});

// Quantity Selector
const decreaseQuantity = document.getElementById('decrease-quantity');
const increaseQuantity = document.getElementById('increase-quantity');
const quantityInput = document.getElementById('quantity-input');

decreaseQuantity.addEventListener('click', () => {
    let currentValue = parseInt(quantityInput.value);
    if (currentValue > 1) {
        quantityInput.value = currentValue - 1;
    }
});

increaseQuantity.addEventListener('click', () => {
    let currentValue = parseInt(quantityInput.value);
    if (currentValue < 10) {
        quantityInput.value = currentValue + 1;
    }
});

// Add to Cart from Product Cards
const addToCartBtns = document.querySelectorAll('.add-to-cart-btn');

addToCartBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
        e.preventDefault();
        const productCard = btn.closest('.product-card');
        const productTitle = productCard.querySelector('h3').textContent;
        const productPrice = parseFloat(productCard.querySelector('.current-price').textContent.replace('$', ''));
        const sizeSelect = productCard.querySelector('.size-select');
        const size = sizeSelect ? sizeSelect.value : '';
        
        if (sizeSelect && !size) {
            alert('Please select a size');
            return;
        }
        
        addToCart(productTitle, productPrice, size, 1);
        updateCartDisplay();
        showCartNotification();
    });
});

// Add to Cart from Modal
const addToCartModal = document.querySelector('.add-to-cart-modal');

addToCartModal.addEventListener('click', () => {
    const productTitle = document.getElementById('modal-product-title').textContent;
    const productPrice = parseFloat(document.getElementById('modal-product-price').textContent.replace('$', ''));
    const size = document.getElementById('modal-size-select').value;
    const quantity = parseInt(document.getElementById('quantity-input').value);
    
    if (!size) {
        alert('Please select a size');
        return;
    }
    
    addToCart(productTitle, productPrice, size, quantity);
    updateCartDisplay();
    showCartNotification();
    productModal.style.display = 'none';
});

// Add to Cart Function
function addToCart(title, price, size, quantity) {
    const existingItem = cart.find(item => 
        item.title === title && item.size === size
    );
    
    if (existingItem) {
        existingItem.quantity += quantity;
    } else {
        cart.push({
            title: title,
            price: price,
            size: size,
            quantity: quantity
        });
    }
    
    updateCartTotal();
    updateCartCount();
}

// Update Cart Total
function updateCartTotal() {
    cartTotal = cart.reduce((total, item) => {
        return total + (item.price * item.quantity);
    }, 0);
}

// Update Cart Count
function updateCartCount() {
    const cartCount = document.getElementById('cart-count');
    const totalItems = cart.reduce((total, item) => {
        return total + item.quantity;
    }, 0);
    cartCount.textContent = totalItems;
}

// Update Cart Display
function updateCartDisplay() {
    const cartItems = document.getElementById('cart-items');
    const cartTotalElement = document.getElementById('cart-total');
    
    cartItems.innerHTML = '';
    
    if (cart.length === 0) {
        cartItems.innerHTML = '<p>Your cart is empty</p>';
    } else {
        cart.forEach((item, index) => {
            const cartItem = document.createElement('div');
            cartItem.className = 'cart-item';
            cartItem.innerHTML = `
                <div class="cart-item-info">
                    <h4>${item.title}</h4>
                    <p>Size: ${item.size} | Qty: ${item.quantity}</p>
                    <p>$${(item.price * item.quantity).toFixed(2)}</p>
                </div>
                <button class="remove-item" data-index="${index}">
                    <i class="fas fa-trash"></i>
                </button>
            `;
            cartItems.appendChild(cartItem);
        });
        
        // Add remove functionality
        const removeBtns = document.querySelectorAll('.remove-item');
        removeBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                const index = parseInt(btn.dataset.index);
                cart.splice(index, 1);
                updateCartDisplay();
                updateCartTotal();
                updateCartCount();
            });
        });
    }
    
    cartTotalElement.textContent = `$${cartTotal.toFixed(2)}`;
}

// Show Cart Notification
function showCartNotification() {
    const notification = document.createElement('div');
    notification.className = 'cart-notification';
    notification.textContent = 'Item added to cart!';
    notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: #28a745;
        color: white;
        padding: 1rem 2rem;
        border-radius: 5px;
        z-index: 1003;
        animation: slideIn 0.3s ease;
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.style.animation = 'slideOut 0.3s ease';
        setTimeout(() => {
            document.body.removeChild(notification);
        }, 300);
    }, 2000);
}

// Checkout Button
const checkoutBtn = document.querySelector('.checkout-btn');

checkoutBtn.addEventListener('click', () => {
    if (cart.length === 0) {
        alert('Your cart is empty');
        return;
    }
    
    // Here you would typically redirect to a checkout page
    // For now, we'll show a simple alert
    alert('Redirecting to checkout...\n\nThis would typically integrate with a payment processor like Stripe or PayPal.');
});

// Add CSS animations
const style = document.createElement('style');
style.textContent = `
    @keyframes slideIn {
        from {
            transform: translateX(100%);
            opacity: 0;
        }
        to {
            transform: translateX(0);
            opacity: 1;
        }
    }
    
    @keyframes slideOut {
        from {
            transform: translateX(0);
            opacity: 1;
        }
        to {
            transform: translateX(100%);
            opacity: 0;
        }
    }
    
    .cart-item {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 1rem 0;
        border-bottom: 1px solid #eee;
    }
    
    .cart-item:last-child {
        border-bottom: none;
    }
    
    .cart-item-info h4 {
        margin: 0 0 0.5rem 0;
        font-size: 1rem;
        color: #333;
    }
    
    .cart-item-info p {
        margin: 0.25rem 0;
        font-size: 0.9rem;
        color: #666;
    }
    
    .remove-item {
        background: #dc3545;
        color: white;
        border: none;
        padding: 0.5rem;
        border-radius: 50%;
        cursor: pointer;
        transition: background 0.3s ease;
    }
    
    .remove-item:hover {
        background: #c82333;
    }
`;
document.head.appendChild(style);

// Initialize cart display
updateCartDisplay();
updateCartCount();

// Merchandise Cart Functionality
document.addEventListener('DOMContentLoaded', function() {
    // Add to cart buttons
    const addToCartButtons = document.querySelectorAll('.feature-card .btn-primary');
    
    addToCartButtons.forEach(button => {
        button.addEventListener('click', function() {
            const card = this.closest('.feature-card');
            const productName = card.querySelector('h3').textContent;
            const productPrice = card.querySelector('.product-price').textContent;
            
            alert(`${productName} added to cart! Price: ${productPrice}`);
            
            // Update button text temporarily
            const originalText = this.innerHTML;
            this.innerHTML = '<i class="fas fa-check"></i> Added!';
            this.style.background = '#28a745';
            
            setTimeout(() => {
                this.innerHTML = originalText;
                this.style.background = '';
            }, 2000);
        });
    });
    
    // Quantity buttons
    const quantityBtns = document.querySelectorAll('.quantity-btn');
    
    quantityBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            const quantitySpan = this.parentElement.querySelector('span');
            let quantity = parseInt(quantitySpan.textContent);
            
            if (this.textContent === '+') {
                quantity++;
            } else if (this.textContent === '-' && quantity > 1) {
                quantity--;
            }
            
            quantitySpan.textContent = quantity;
            updateCartTotal();
        });
    });
    
    // Remove buttons
    const removeBtns = document.querySelectorAll('.remove-btn');
    
    removeBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            const cartItem = this.closest('.cart-item');
            cartItem.remove();
            updateCartTotal();
        });
    });
    
    // Update cart total
    function updateCartTotal() {
        const cartItems = document.querySelectorAll('.cart-item');
        let subtotal = 0;
        
        cartItems.forEach(item => {
            const price = parseFloat(item.querySelector('.item-price').textContent.replace('$', ''));
            const quantity = parseInt(item.querySelector('.item-quantity span').textContent);
            subtotal += price * quantity;
        });
        
        const shipping = 5.99;
        const total = subtotal + shipping;
        
        // Update summary
        const summaryItems = document.querySelectorAll('.summary-item');
        summaryItems[0].querySelector('span:last-child').textContent = `$${subtotal.toFixed(2)}`;
        summaryItems[2].querySelector('span:last-child').textContent = `$${total.toFixed(2)}`;
    }
}); 