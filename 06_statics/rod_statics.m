function rod_statics(mw)

    % This is the TCA static, 
    % the external force is prescribed as an boundary
    % condition. The force is increased step by step. 
    % using a bvp4c to solve the BVP problem
    % 10/05/2020 copied from function TCA_pass_stat_4c.m
    % borrow something from TCA_act_stat.m 
    % change all alpha_c to alpha
    % 10/6/2020 considering change of the coil radius
    % 10/7/2020 simulation works. Match results. 
    % 10/28/2020 
    % 12/7 modified for hanging weight simulation
    % 12/8 include the fiber actuation model
    % 12/10 modify to make a general code for different weights. 
    % 12/14 roll back to the old constitutive law. 
    % 12/18/2020 revised to incorporate another type of TCA
    % 1/13/2021 modify the model to solve the problem using Lie group
    % formulation
    
    
    % Inputs
    T = (25:5:160)'; 
    mg = mw/1000*9.8; % mw is the weight in grams
    F = [0:0.005:mg, mg];
    
    % Geometry property
    [l_t, l_star, r_star, alpha_star, theta_bar_star, r_t, N, alpha_min] = TCA_geo(mw);
    
    % Use 10 coils to accelerate the simulation.
    N_sim = 10; N_per_coil = 20; 
    Ns = N_per_coil*(N_sim); % Number of nodes   
    N_scale = N/N_sim; l_t = l_t/N_scale; 
    l_star = l_star/N_scale; 
    
    % Material property
    [EI, EA, GJ, GA, ~] = TCA_moduli_creeped(25, mw);% 
    alpha_star = - alpha_star; 
    K = [EI, EI, GJ, GA, GA, EA]'; 
    
    % Reference twists
    v_0 = [0; 0; 1];   
    u_0 = @(s)  [    (sin(theta_bar_star*s)*cos(alpha_star)^2)/r_star
                  (cos(theta_bar_star*s)*cos(alpha_star)^2)/r_star
                  sin(2*alpha_star)/(2*r_star) ];
     xi_0 = @(s) [u_0(s);  v_0]; 
    %Boundary Conditions

    p0 = [r_star; 0; 0];
    R0 = [ -1,             0,            0;
            0,  -sin(alpha_star), cos(alpha_star);
            0,  cos(alpha_star), sin(alpha_star)];
    h0 = rotm2quat(R0)';
    Mext = [0; 0; 0]; % momentum at the tip, N*mm
    Fext = [0; 0; 0]; % force at the tip 
    MN = zeros(6,1);
    % Main Simulation %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    % Initialization
    solinit = bvpinit(linspace(0,l_t,Ns),@init);
    options = bvpset('Stats','off','RelTol',1e-5, 'NMax', 5000);
    N_step = length(T);
    l = ones(N_step, 1)*l_star;
    N_step1 = length(F);
    % iterate to the equilibrium with the after hanging the weigth. 
    for i  = 1:N_step1  % commont this part if we can load the data
       fprintf('preloading %d/%d \n', i, N_step1);
       Fext(3)=  - F(i);       
       sol = bvp5c(@static_ODE,@bc1,solinit,options);
       solinit = bvpinit(sol,[0 l_t]);
       visualize(sol.y);
       clf;
    end

    alpha = asin(norm(sol.y(1:3, end) - sol.y(1:3, 1))/l_t);
 
    for i = 1:N_step
        fprintf('%d/%d \n', i, N_step); 
         % update parameters 
        [EI, EA, GJ, GA, D_theta_bar] = TCA_moduli_creeped(T(i),  mw);% V_f = 0.4
        K =[EI, EI, GJ, GA, GA, EA]';
        % detect contact
        
        if(alpha > alpha_min)
            theta_bar = D_theta_bar;         
        else
             theta_bar = theta_bar +  20*exp(50*(alpha-alpha_min)); 
             fprintf('Reach the minimum length'); 
        end
    
        xi_0 = @(s)  [    0;
                          cos(alpha_star)^2/r_star;
                          sin(2*alpha_star)/(2*r_star)+ theta_bar ; 0;0;1];
        solinit = bvpinit(sol,[0 l_t]);
        sol = bvp5c(@static_ODE,@bc1,solinit,options); % used constrained BC
        
        % The solution at the mesh points
        ysol = sol.y; % we don't need arclength anymore. 
        l(i) = norm(ysol(1:3, end) - ysol(1:3, 1));
        alpha = asin(l(i)/l_t); %** this is IMPORTANT, update 
        visualize(ysol);
        % update the twist 
        clf;
    end
    x = -N_scale*(l-l(1));
    cd 'C:\MATLAB\TCA_TRO\06_statics'
    writematrix([T, x], Name);
    plot(T,  x); 
    
    
    function y = init(s)
    
        y = [   r_star*cos((s*cos(alpha_star))/r_star)
                r_star*sin((s*cos(alpha_star))/r_star)
                s*sin(alpha_star)
                h0
                Mext
                Fext];
    end
    
    function res = bc1(ya,yb)
         
        res = [ ya(1:7) - [p0; h0];
                Adg(yb(1:7))*yb(8:13) - [Mext; Fext]];%
    end
        

    function ys = static_ODE(s,y)
        % this is still required if the initial state is preloaded. 
        % This is another formulation using m and n as
        % varilables 
        
        h = y(4:7);
        R = h2R(h);
        Wi = y(8:13); % Wi  = [m,n] First component is the angular
        xi = K.^-1.*Wi + xi_0(s); 
        u = xi(1:3); 
        v = xi(4:6);
        
        ps = R*v;
        hs = h_diff(u, h);
        Wis = ad(xi)'*Wi; % ignore the distribued force
        ys = [ps; hs; Wis];
    %    MN = Adg(y(1:7))'*[Mext; Fext]; 
        
    end

    
    function R = h2R(h)
        %Quaternion to Rotation for integration
        h1=h(1);
        h2=h(2);
        h3=h(3);
        h4=h(4);
        R = eye(3) + 2/(h'*h) * ...
            [-h3^2-h4^2  , h2*h3-h4*h1,  h2*h4+h3*h1;
            h2*h3+h4*h1, -h2^2-h4^2 ,  h3*h4-h2*h1;
            h2*h4-h3*h1, h3*h4+h2*h1, -h2^2-h3^2  ];
    end

    function hs = h_diff(u, h)
        % Calculate the derivative of the quaternion. 
        % if u to hs, if w we get ht
             hs = [ 0,    -u(1), -u(2), -u(3);
                    u(1),   0  ,  u(3), -u(2);
                    u(2), -u(3),   0  ,  u(1);
                    u(3),  u(2), -u(1),   0  ] * h/2;
    end

    %Function Definitions
    function visualize(y)
        plot3(y(1,:),y(2,:),y(3,:)); hold on
        plot3(y(1,end),y(2,end),y(3,end), 'ro', 'MarkerSize',10)
        title('TCA Dynamics');
        xlabel('x (m)');
        ylabel('y (m)');
        zlabel('z (m)');
        axis([-r_star*5 r_star*5 -r_star*5 r_star*5 -1.5*l_star 0]);
        grid on;
        % view(0,0)
        daspect([1 1 1]);
        set(gcf, 'Units', 'Normalized', 'OuterPosition', [.45,0, .55, 1]);
        drawnow;
    end
    
    function Adg = Adg(ph)
        % ph is a vector ph = [p; h]; 
        p = ph(1:3); 
        h = ph(4:7);
        R = h2R(h);        
        Adg = [R, zeros(3,3); skew(p)* R, R];
        
    end
  

end